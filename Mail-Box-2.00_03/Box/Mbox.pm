
use strict;
package Mail::Box::Mbox;

use base 'Mail::Box';
our $VERSION = 2.00_03;

use Mail::Box::Mbox::Message;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use FileHandle;
use File::Copy;
use File::Spec;
use POSIX ':unistd_h';
use Carp;

=head1 NAME

Mail::Box::Mbox - Handle folders in Mbox format

=head1 SYNOPSIS

   use Mail::Box::Mbox;
   my $folder = Mail::Box::Mbox->new(folder => $ENV{MAIL}, ...);

=head1 DESCRIPTION

This documentation describes how Mbox mailboxes work, and also describes
what you can do with the Mbox folder object C<Mail::Box::Mbox>.
Please read C<Mail::Box::Manager> and C<Mail::Box> first.

=head2 How Mbox folders work

Mbox folders store many messages in one file (let's call this a
`file-based' folder, in comparison to a `directory-based' folder type
like MH).

In file-based folders, each message begins with a line which starts with
the string C<From >.  Lines inside a message which accidentally start with
C<From> are, in the file, preceeded by `E<gt>'. This character is stripped
when the message is read.

In this module, the name of a folder may be an absolute or relative path.
You can also preceed the foldername by C<=>, which means that it is
relative to the I<folderdir> option specified for the C<new> method.

=head2 Simulation of sub-folders

File-based folders do not really have a sub-folder concept as directory-based
folders do, but this module tries to simulate them.  In this implementation
a directory like

   Mail/subject1/

is taken as an empty folder C<Mail/subject1>, with the folders in that
directory as sub-folders for it.  You may also use

   Mail/subject1
   Mail/subject1.d/

where C<Mail/subject1> is the folder, and the folders in the
C<Mail/subject1.d> directory are used as sub-folders.  If your situation
is similar to the first example and you want to put messages in that empty
folder, the directory is automatically (and transparently) renamed, so
that the second situation is reached.

Because of these simulated sub-folders, the folder manager does not need to
distinguish between file- and directory-based folders in this respect.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  Many options are taken from object-classes to which
Mail::Box::Mbox is an extension.  Read below for a detailed
description of Mbox specific options.

 OPTION              DESCRIBED IN       DEFAULT
 access              Mail::Box          'r'
 body_type           Mail::Box          'Mail::Message::Body'
 create              Mail::Box          0
 folder              Mail::Box          $ENV{MAIL}
 folderdir           Mail::Box          $ENV{HOME}.'/Mail'
 head_type           Mail::Box          'Mail::Message::Head'
 head_fold           Mail::Box          72
 head_partial_type   Mail::Box          head_type . '::Partial'
 lazy_extract        Mail::Box          10kb
 lockfile            Mail::Box::Locker  foldername.lock-extension
 lock_extension      Mail::Box::Mbox    '.lock'
 lock_method         Mail::Box::Locker  'DOTLOCK'
 lock_timeout        Mail::Box::Locker  1 hour
 lock_wait           Mail::Box::Locker  10 seconds
 log                 Mail::Reporter     'WARNINGS'
 manager             Mail::Box          undef
 message_type        Mail::Box          'Mail::Box::Mbox::Message'
 organization        Mail::Box          'FILE'
 remove_when_empty   Mail::Box          1
 save_on_exit        Mail::Box          1
 subfolder_extension Mail::Box::Mbox    '.d'
 take_headers        Mail::Box          <quite some>
 trace               Mail::Reporter     'WARNINGS'
 <none>              Mail::Box::Tie

Mbox specific options:

=over 4

=item * lock_extension =E<gt> FILENAME|STRING

When the dotlock locking mechanism is used, the lock is created by
the creation of a file.  For C<Mail::Box::Mbox> type of folders, this
file is by default named the same as the folder-file itself, followed by
C<.lock>.

You may specify an absolute filename, a relative (to the folder's
directory) filename, or an extension (preceeded by a dot).  So valid
examples are:

    .lock                  # append to filename
    my_own_lockfile.test   # full filename, same dir
    /etc/passwd            # somewhere else

=item * subfolder_extension =E<gt> STRING

Mail folders which store their messages in files usually do not
support sub-folders, as do mail folders which store messages
in a directory.

However, this module can simulate sub-directories if the user wants it to.
When a subfolder of folder C<xyz> is created, we create a directory which
is called C<xyz.d> to contain them.  This extension C<.d> can be changed
using this option.

=back

=cut

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
my $default_extension  = '.d';

sub init($)
{   my ($self, $args) = @_;
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{organization}     ||= 'FILE';

    $self->SUPER::init($args);

    my $sub_extension          = $self->{MB_sub_ext}
       = $args->{subfolder_extension} || $default_extension;

    my $filename                = $self->{MB_filename}
       = (ref $self)->folderToFilename
           ( $self->name
           , $self->folderdir
           , $sub_extension
           );

    $self->registerHeaders( qw/status x-status/ );

    my $lockdir   = $filename;
    $lockdir      =~ s!/([^/]*)$!!;
    my $extension = $args->{lock_extension} || '.lock';
    $self->lockFilename
      ( File::Spec->file_name_is_absolute($extension) ? $extension
      : $extension =~ m!^\.!  ? "$filename$extension"
      :                      File::Spec->catfile($lockdir, $extension)
      );

    # Check if we can write to the folder, if we need to.

    if($self->writeable && ! -w $filename)
    {   if(-e $filename)
        {   warn "Folder $filename is write-protected.\n";
            $self->{MB_access} = 'r';
        }
        else
        {   my $create = FileHandle->new($filename, 'w');
            unless($create)
            {   warn "Cannot create folder $filename: $!\n";
                return;
            }
            $create->close;
        }
    }

    $self;
}

#-------------------------------------------

=item fileOpen

=item fileIsOpen

=item fileClose

Open or close the file which keeps the folder.  If the folder is already open,
it will not be opened again.  This method will maintain exclusive locking.
Of course, C<fileIsOpen> only checks if the file is opened or not.

If the lock can not be acquired, a warning is issued and this method
returns C<undef>.

Example:

    my $file = $folder->fileOpen or die;
    $folder->fileClose;

=cut

sub fileOpen()
{   my $self = shift;
    return $self->{MB_file} if exists $self->{MB_file};

    my $source = $self->filename;
    my $file;

    my $access = $self->{MB_access} || 'r';
    $access = 'r+' if $access eq 'rw' || $access eq 'a';

    if($^O eq 'solaris' && $self->lockMethod eq 'FILE' && $access eq 'r')
    {   # An Solaris, excl lock can only be done on file which is opened
        # read-write.

        unless(-w $source)
        {   warn <<'SOLARIS';
ERROR: On Solaris, a file must be writable to lock exclusively.  Please
add write-permission to $source or change locking mode to anything
different from FILE.
SOLARIS

            return undef;
        }

        $access = 'r+';
    }

    $file = Mail::Box::Parser->new
       ( filename  => $source
       , mode      => $access
       , separator => 'FROM'
       , trace     => $self->trace
       );

    return undef unless $file;

    $self->{MB_file} = $file;

    unless($self->lock)
    {   warn "Couldn't get a lock on folder $self (file $source)\n";
        close $file;
        return;
    }

    $file;
}

sub fileIsOpen() { exists shift->{MB_file} }

sub fileClose()
{   my $self = shift;
    my $file = $self->{MB_file} or return $self;

    $self->unlock;
    delete $self->{MB_file};

    $file->close;
    $self;
}

#-------------------------------------------

=item readMessages

Read all messages from the folder.  This method is called during
instantiation of the folder, so do not call it yourself unless you have a
very good reason.

=cut

sub readMessages(@)
{   my $self = shift;

    my $filename = $self->filename;
    $self->{MB_source_mtime} = (stat $filename)[9];

    # On a directory, simulate an empty folder with only subfolders.
    if(-d $filename)
    {   $self->{MB_delayed_loads} = 0;
        return $self;
    }

    my $parser   = $self->getParser  # was fileOpen
        or return $self;

    my $delayed  = 0;
    my $mode     = $self->registeredHeaders;
    my $headtype = ref $mode
                 ? $self->{MB_head_partial_type}->filter(@$mode)
                 : $self->{MB_head_type};

    while(my $head = $headtype->read($parser))
    {
        my $size = $head->guessBodySize;
        my $bodytype
          = $head->isMultipart        ? 'Mail::Message::Body::Multipart'
          : $self->lazyExtract($head, undef, $size)
                                      ? 'Mail::Message::Body::Delayed'
          : ref $self->{MB_body_type} ? $self->{MB_body_type}->($head, $size)
          :                             $self->{MB_body_type};

        my $body = $bodytype->read($parser, $head, $size);
        unless($body)
        {   $body = Mail::Message::Body::String->new(data => '');
            $body->log(ERROR => 'Body could not be read');
            next;
        }

        my $message = $self->{MB_message_type}->new
          ( head => $head
          , body => $body
          );

        next unless $message;
        $delayed++ if $bodytype->isDelayed;

        $message->statusToLabels->XstatusToLabels;
        $self->addMessage($message);
    }

    # Release the folder.

    $self->{MB_delayed_loads} = $delayed;

    $parser->close
        if !$delayed && $self->lockMethod ne 'FILE';

    $self;
}
 
#-------------------------------------------

=item write

Write all messages to the folder-file.  Returns the folder if successful.
If you want to write to a different file, you must first create a new
folder, then move the messages, and then write that file. The following
options may be specified (see C<Mail::Box> for explanation)

=over 4

=item * keep_deleted =E<gt> BOOL

=item * save_deleted =E<gt> BOOL

=item * remove_when_empty =E<gt> BOOL

=back

=cut

sub writeMessages($)
{   my ($self, $args) = @_;
    my $filename = $self->filename;

    my @messages = @{$args->{messages}};

    if(!@messages && $self->{MB_remove_empty})
    {   $self->fileClose;  # on some circumstances this would stop unlink.

        unlink $filename
            or warn "Couldn't remove folder $self (file $filename): $!\n";

        # Can the sub-folder directory be removed?  Don't mind if this
        # doesn't work.
        rmdir $filename . $self->{MB_sub_ext};

        return $self;
    }

    my $tmpnew   = $self->tmpNewFolder($filename);
    my $was_open = $self->fileIsOpen;
    if($self->{MB_delayed_loads} && ! $self->fileOpen)
    {   warn "Where did the folder-file $self (file $filename) go?\n";
        return;
    }

    my $new = FileHandle->new($tmpnew, 'w');
    unless($new)
    {   warn "Unable to write to file $tmpnew for folder $self: $!\n";
        $self->fileClose unless $was_open;
        return;
    }

    $_->migrate($new) foreach @messages;

    $new->close;
    $self->fileClose unless $was_open;

    move $tmpnew, $filename
       or warn "Could not replace $filename by $tmpnew, to update $self: $!\n";

    $self;
}

#-------------------------------------------

=item appendMessages OPTIONS

(Class method) Append one or more messages to a folder. Messages are just
appended to the folder-file--the folder is not read.  This means that
duplicate messages can exist in a folder.

If the folder does not exist, C<undef> (or FALSE) is returned.

=over 4

=item * folder =E<gt> FOLDERNAME

=item * message =E<gt> MESSAGE

=item * messages =E<gt> ARRAY-OF-MESSAGES

=back

Example:

    my $message = Mail::Internet->new(...);
    Mail::Box::Mbox->appendMessages
      ( folder    => '=xyz'
      , message   => $message
      , folderdir => $ENV{FOLDERS}
      );

=cut

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message} ? $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $folder = $class->new(@_, access => 'a');
    my $file   = $folder->fileOpen or return;

    $folder->lock;

    seek $file, 0, SEEK_END;

    foreach (@messages)
    {   # I would like to coerce here, into the correct message type.  However,
        # the folder has not been opened, so what is the correct type?  Instead
        # of a real conversion, we have hope that each message just starts
        # with a from-line
        # $class->coerce($_);   # sorry, can't
 
        $file->print( $_->can('fromLine')
                    ? $_->fromLine
                    : $_->Mail::Box::Mbox::Message::fromLine
                    );

        $_->print($file);
        $file->print("\n");
    }

    $folder->fileClose;
    $folder->close;

    $class;
}

#-------------------------------------------

sub close(@)
{   my $self = $_[0];            # be careful, we want to set the calling
    undef $_[0];                 #    ref to undef, as the SUPER does.
    shift;
    $self->SUPER::close(@_);
    $self->fileClose;
}

#-------------------------------------------

=item filename

Returns the filename for this folder.

Example:

    print $folder->filename;

=cut

sub filename() { shift->{MB_filename} }

#-------------------------------------------

=item filehandle

Returns the filehandle for this folder.

Example:

    print $folder->filehandle;

=cut

sub filehandle() { shift->{MB_file} }

#-------------------------------------------

=item folderToFilename FOLDERNAME, FOLDERDIR, EXTENSION

(Class method)  Translate a folder name into a filename, using the
FOLDERDIR value to replace a leading C<=>.

=cut

sub folderToFilename($$$)
{   my ($class, $name, $folderdir, $extension) = @_;
    $name =~ s#^=#$folderdir/#;
    my @parts = split m!/!, $name;
    my $real  = shift @parts;

    while(@parts)
    {   my $next         = shift @parts;
        my $real_next    = File::Spec->catfile($real, $next);
        my $realext_next = File::Spec->catfile($real.$extension, $next);
        $real = -e $real_next               ? $real_next
              : -e $realext_next            ? $realext_next
              : -e $realext_next.$extension ? $realext_next
              : -d "$real$extension"        ? $realext_next
              :                               $real_next;
    }
    $real;
}

sub tmpNewFolder($) { shift->filename . '.tmp' }

#-------------------------------------------

=back

=head2 folder management methods

Read the C<Mail::Box> documentation for more details and more options
for each method.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

Automatically determine if the the folder specified by FOLDERNAME is a
C<Mail::Box::Mbox> folder.  The FOLDERNAME specifies the name of the folder
as specified by the application.  OPTIONS is a reference to a hash with
extra information for the request.  For this class, we use (if defined):

=over 4

=item * folderdir =E<gt> DIRECTORY

=item * subfolder_extension =E<gt> STRING

=back

Example:

   Mail::Box::Mbox->foundIn
      ( '=markov'
      , folderdir => "$ENV{HOME}/Mail"
      );

=cut

sub foundIn($@)
{   my ($class, $name, %args) = @_;
    $name ||= $args{folder} || return;

    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    if(-d $filename)      # fake empty folder, with sub-folders
    {   return 1 unless -f "$filename/1";
    }

    return 0 unless -f $filename;
    return 1 if -z $filename;      # empty folder is ok

    my $file = FileHandle->new($filename, 'r') or return 0;
    local $_;                      # Save external $_
    while(<$file>)
    {   next if /^\s*$/;
        $file->close;
        return m/^From /;
    }

    return 1;
}

#-------------------------------------------

=item create FOLDERNAME [, OPTIONS]

(Class method) Create a folder.  If the folder already exists, it will
be left unmodified.  You may specify the following options:

=over 4

=item * folderdir =E<gt> DIRECTORY

=back

=cut

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    return $class if -f $filename;

    if(-d $filename)
    {   # sub-dir found, start simulate sub-folders.
        move $filename, $filename . $extension;
    }

    unless(open CREATE, ">$filename")
    {   warn "Cannot create folder $name: $!\n";
        return;
    }

    CORE::close CREATE;
    $class;
}

#-------------------------------------------

=item listFolders [OPTIONS]

(Class OR Instance method) List the folders in a certain directory.  This
method can be called on the class, in which case you specify the base
folder where the sub-folders must be retrieved from by name.  When used
on an instance of the class, the sub-folders of the instance are returned.

Folders will not start with a dot.  When a directory without the sub-folder
extension is found, then an empty folder is assumed.

=over 4

=item * folder =E<gt> FOLDERNAME

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

=item * skip_empty =E<gt> BOOL

=item * subfolder_extension =E<gt> STRING

=back

=cut

sub listFolders(@)
{   my ($thingy, %args)  = @_;
    my $class      = ref $thingy || $thingy;

    my $skip_empty = $args{skip_empty} || 0;
    my $check      = $args{check}      || 0;
    my $extension  = $args{subfolder_extension} || $default_extension;

    my $folder     = exists $args{folder} ? $args{folder} : '=';
    my $folderdir  = exists $args{folderdir}
                   ? $args{folderdir}
                   : $default_folder_dir;

    my $dir        = ref $thingy  # Mail::Box::Mbox
                   ? $thingy->filename
                   : $class->folderToFilename($folder, $folderdir, $extension);

    my $real       = -d $dir ? $dir : "$dir$extension";
    return () unless opendir DIR, $real;

    # Some files have to be removed because they are created by all
    # kinds of programs, but are no folders.

    my @entries = grep { ! m/\.lo?ck$/ && ! m/^\./ } readdir DIR;
    closedir DIR;

    # Look for files in the folderdir.  They should be readible to
    # avoid warnings for usage later.  Furthermore, if we check on
    # the size too, we avoid a syscall especially to get the size
    # of the file by performing that check immediately.

    my %folders;  # hash to immediately un-double names.

    foreach (@entries)
    {   my $entry = File::Spec->catfile($real, $_);
        next unless -r $entry;
        if( -f _ )
        {   next if $args{skip_empty} && ! -s _;
            next if $args{check} && !$class->foundIn($entry);
            $folders{$_}++;
        }
        elsif( -d _ )
        {   # Directories may create fake folders.
            if($args{skip_empty})
            {   opendir DIR, $entry or next;
                my @sub = grep !/^\./, readdir DIR;
                closedir DIR;
                next unless @sub;
            }

            (my $folder = $_) =~ s/$extension$//;
            $folders{$folder}++;
        }
    }

    keys %folders;
}

#-------------------------------------------

=item openSubFolder NAME [,OPTIONS]

Open (or create, if it does not exist yet) a new subfolder in an
existing folder.

Example:

    my $folder = Mail::Box::Mbox->new(folder => '=Inbox');
    my $sub    = $folder->openSubFolder('read');
 
=cut

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->SUPER::openSubFolder(@_, folder => $self->name . '/' .$name);
}

#-------------------------------------------

#=item scanForMessages MESSAGE, MESSAGE-IDS, TIMESTAMP, WINDOW
# Not needed for Mboxes: we have all headers from the start.
# This method overrules the default complex scanning.
#=cut

sub scanForMessages(@) {shift};

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_03

=cut

1;
