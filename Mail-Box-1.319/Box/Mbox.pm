
use strict;
use Mail::Box;
use Mail::Box::Mbox::Message;

package Mail::Box::Mbox;
use vars qw/@ISA/;
@ISA     = 'Mail::Box';

use FileHandle;
use File::Copy;
use File::Spec;
use POSIX ':unistd_h';
use Carp;

=head1 NAME

Mail::Box::Mbox - Handle folders with many messages per file.

=head1 SYNOPSIS

   use Mail::Box::Mbox;
   my $folder = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

This manual-page describes Mail::Box::Mbox and Mail::Box::Mbox::*
packages.  Read Mail::Box::Manager and Mail::Box first.

=head2 How Mbox-folders work

Mbox folders store many messages in one file (let's call this a
`file-based' folder, in contrary to a `directory-based' foldertype
like MH).

In file-based folders, each message is preceeded by a line which starts
with the word C<From >.  Lines inside a message which do accedentally
start with C<From> are, in the file, preceeded by `E<gt>'.  This character is
stripped when the message is read.

The name of a folder may be an absolute or relative path.  You can also
preceed the foldername by C<=>, which means that it is relative to the
I<folderdir> as specified at C<new>.

=head2 Simulation of sub-folders

File-based folders do not really have a sub-folder idea, as directory-based
folders have, but this module tries to simulate them.  In this implementation
a directory like

   Mail/subject1/

is taken as an empty folder C<Mail/subject1>, with the folders in that
directory as sub-folders for it.  You may also use

   Mail/subject1
   Mail/subject1.d/

where C<Mail/subject1> is the folder, and the folders in the C<Mail/subject1.d>
directory are used as sub-folders.  If your situation is as in the first
example and you want to put messages in that empty folder, the directory is
automatically renamed, such that the second situation is reached.

Because of these simulated sub-folders, the folder-manager does not need to
distiguish between file- and directory-based folders in this respect.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  Many options are taken from object-classes which
Mail::Box::Mbox is an extention of.  Read below for a detailed
description of Mbox specific options.

 access            Mail::Box          'r'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          $ENV{HOME}.'/Mail'
 lazy_extract      Mail::Box          10kb
 lockfile          Mail::Box::Locker  foldername.lock-extention
 lock_extention    Mail::Box::Mbox    '.lock'
 lock_method       Mail::Box::Locker  'DOTLOCK'
 lock_timeout      Mail::Box::Locker  1 hour
 lock_wait         Mail::Box::Locker  10 seconds
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::Mbox::Message'
 notreadhead_type  Mail::Box          'Mail::Box::Message::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::Mbox::NotParsed'
 organization      Mail::Box          'FILE'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 subfolder_extention Mail::Box::Mbox  '.d'
 take_headers      Mail::Box          <quite some>
 <none>            Mail::Box::Tie

Mbox specific options:

=over 4

=item * lock_extention =E<gt> FILENAME|STRING

When the dotlock locking mechanism is used, the lock is created by
the creation of a file.  For Mail::Box::Mbox type of folders, this
file is by default named as the folder-file itself, followed by
C<.lock>.

You may specify an absolute filename, a relative (to the folder's
directory) name, or an extention (preceeded by a dot).  So valid examples
are:

    .lock                  # append to filename
    my_own_lockfile.test   # full filename, same dir
    /etc/passwd            # somewhere else

=item * subfolder_extention =E<gt> STRING

Mail folders which store their messages in files do usually not
support sub-folders, as known by mail folders which store messages
in a directory.

However, we simulate sub-directories if the user wants us to.  When
a subfolder of folder C<xyz> is created, we create a directory
which is called C<xyz.d> to contain them.  This extention C<.d>
can be changed using this option.

=back

=cut

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
my $default_extention  = '.d';

sub init($)
{   my ($self, $args) = @_;
    $args->{notreadhead_type} ||= 'Mail::Box::Message::NotReadHead';
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{organization}     ||= 'FILE';

    $self->SUPER::init($args);

    my $extention               = $self->{MB_sub_ext}
       = $args->{subfolder_extention} || $default_extention;

    my $filename                = $self->{MB_filename}
       = (ref $self)->folderToFilename
           ( $self->name
           , $self->folderdir
           , $extention
           );

    $self->registerHeaders( qw/status x-status/ );

    my $lockdir  = $filename;
    $lockdir     =~ s!/([^/]*)$!!;
    my $extent   = $args->{lock_extention} || '.lock';
    $self->lockFilename
      ( File::Spec->file_name_is_absolute($extent) ? $extent
      : $extent =~ m!^\.!  ? "$filename$extent"
      :                      File::Spec->catfile($lockdir, $extent)
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

Open/close the file which keeps the folder.  If the folder is already open,
it will not be opened again.  This method will maintain exclusive locking.
Of course, C<fileIsOpen> only checks if the file is opened or not.

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

    return undef
        unless $file = FileHandle->new($source, $access);

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

Read all messages from the folder.  This method is called at instantiation
of the folder, so do not call it yourself unless you have a very good
reason.

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

    my $file = $self->fileOpen || return;

    # Prepare to scan for headers we want.  To speed things up, we create
    # a regular expression which will only fit exact on the right headers.
    # The only thing to do when the line fits is to lowercase the fieldname.

    my $mode = $self->registeredHeaders;
    $mode = 'REAL' if $mode eq 'DELAY';

    my ($expect, $take, $take_headers);

    if(ref $mode)
    {   # If the user specified a list of fields, we prepare a regexp
        # which can match thid really fast.
        $expect = [ keys %$mode ];
        $mode   = 'SOME';
        $take   = '^(' . join('|', @$expect) . ')\:\s*(.*)$';
        $take_headers = qr/$take/i;
    }

    # Prepare the parser.

    my $parser     = $self->parser;
    my $delayed    = 0;

    local $_;
    my $from_line  = $file->getline;
    my $end;

    while($from_line)
    {
        my $begin = $file->tell;

        # Detect header.
        my @header;
        while(<$file>)
        {   last if /^\r?\n$/;
            push @header, $_;
        }
        last unless @header;

        # Detect body

        $end = $begin;
        my @body;

        while(<$file>)
        {   last if m/^From(\s|\s.*\s)(19|20)\d\d(\s|$)/;
            push @body, $_;
            $end = $file->tell;
        }

        # a pitty that an MIME::Entity does not split new and init...

        my $size    = $end - $begin;
#       chomp $from_line;

        my @options =
          ( @{$self->{MB_message_opts}}
          , from         => $from_line
          , begin        => $begin
          , size         => $size
          );

        $from_line     = $_;               # catch for next message.

        my $message;
        if(not $self->lazyExtract(\@header, \@body, $size))
        {   #
            # Take the message immediately.
            #

            # Process all escapped from-lines.
            s/^\>(?=[fF]rom )// foreach @body;

            my $parsed;
            eval {$parsed = $parser->parse_data( [@header, "\n", @body] ) };
            my $error = $@ || $parser->last_error;
            if($error)
            {   warn "error $error.\n";
            }
            else
            {   $message = $self->{MB_message_type}->new
                  ( message => $parsed
                  , @options
                  );
            }
        }
        elsif($mode eq 'SOME' || $mode eq 'ALL')
        {   #
            # Create delay-loaded message with some fields.
            #

            # Get all header lines for fast access.
            my $header = $self->{MB_notreadhead_type}->new(expect => $expect); 
            $self->unfoldHeaders(\@header);

            if($mode eq 'SOME')
            {   foreach (@header)
                {   $header->setField($1, $2) if $_ =~ $take_headers;
                }
            }
            else {  $header->setField(split ':', $_, 2) foreach @header }

            $message = $self->{MB_notparsed_type}->new
              ( head       => $header
              , upgrade_to => $self->{MB_message_type}
              , @options
              );
            $header->message($message);

            $delayed++;
        }
        else
        {   #
            # Create a real header structure, but not yet the body.
            #

            $message = $self->{MB_notparsed_type}->new
              ( head       => MIME::Head->new(\@header)->unfold
              , upgrade_to => $self->{MB_message_type}
              , @options
              );

            $delayed++;
        }

        next unless $message;

        $message->statusToLabels->XstatusToLabels;
        $self->addMessage($message);
    }

    # Release the folder.

    $self->{MB_delayed_loads} = $delayed;

    $self->fileClose
        if !$delayed && $self->lockMethod ne 'FILE';

    $self;
}
 
#-------------------------------------------

=item write

Write all messages to the folder-file.  Returns the folder when this
was successful.  If you want to write to a different file, you
first create a new folder, then move the messages, and then write
that file. As options you may specify (see C<Mail::Box> for explanation)

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

(Class method) Append one or more messages to a folder.  The folder
will not be read, but messages are just appended to the folder-file.
This also means that double messages can exist in a folder.

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

Returns the filename related to this folder.

Example:

    print $folder->filename;

=cut

sub filename() { shift->{MB_filename} }

#-------------------------------------------

=item filehandle

Returns the filehandle related to this folder.

Example:

    print $folder->filehandle;

=cut

sub filehandle() { shift->{MB_file} }

#-------------------------------------------

=item folderToFilename FOLDERNAME, FOLDERDIR, EXTENTION

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToFilename($$$)
{   my ($class, $name, $folderdir, $extention) = @_;
    $name =~ s#^=#$folderdir/#;
    my @parts = split m!/!, $name;
    my $real  = shift @parts;

    while(@parts)
    {   my $next         = shift @parts;
        my $real_next    = File::Spec->catfile($real, $next);
        my $realext_next = File::Spec->catfile($real.$extention, $next);
        $real = -e $real_next               ? $real_next
              : -e $realext_next            ? $realext_next
              : -e $realext_next.$extention ? $realext_next
              : -d "$real$extention"        ? $realext_next
              :                               $real_next;
    }
    $real;
}

sub tmpNewFolder($) { shift->filename . '.tmp' }

#-------------------------------------------

=back

=head2 folder management methods

Read the Mail::Box manual for more details and more options
on each method.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

Autodetect if there is a Mail::Box::Mbox folder specified here.  The
FOLDERNAME specifies the name of the folder, as is specified by the
application.  ARGS is a reference to a hash with extra information
on the request.  For this class, we use (if defined):

=over 4

=item * folderdir =E<gt> DIRECTORY

=item * subfolder_extention =E<gt> STRING

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
    my $extention = $args{subfolder_extention} || $default_extention;
    my $filename  = $class->folderToFilename($name, $folderdir, $extention);

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
be left untouched.  As options, you may specify:

=over 4

=item * folderdir =E<gt> DIRECTORY

=back

=cut

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extention = $args{subfolder_extention} || $default_extention;
    my $filename  = $class->folderToFilename($name, $folderdir, $extention);

    return $class if -f $filename;

    if(-d $filename)
    {   # sub-dir found, start simulate sub-folders.
        move $filename, $filename . $extention;
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
folder where the sub-folders must be retreived from as name.  When used
on an instance, the sub-folders of the instance are returned.

Folders will not start with a dot.  When a directory without the sub-folder
extention is found, then an empty folder is presumed.

=over 4

=item * folder =E<gt> FOLDERNAME

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

=item * skip_empty =E<gt> BOOL

=item * subfolder_extention =E<gt> STRING

=back

=cut

sub listFolders(@)
{   my ($thingy, %args)  = @_;
    my $class      = ref $thingy || $thingy;

    my $skip_empty = $args{skip_empty} || 0;
    my $check      = $args{check}      || 0;
    my $extent     = $args{subfolder_extention} || $default_extention;

    my $folder     = exists $args{folder} ? $args{folder} : '=';
    my $folderdir  = exists $args{folderdir}
                   ? $args{folderdir}
                   : $default_folder_dir;

    my $dir        = ref $thingy  # Mail::Box::Mbox
                   ? $thingy->filename
                   : $class->folderToFilename($folder, $folderdir, $extent);

    my $real       = -d $dir ? $dir : "$dir$extent";
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

            (my $folder = $_) =~ s/$extent$//;
            $folders{$folder}++;
        }
    }

    keys %folders;
}

#-------------------------------------------

=item openSubFolder NAME [,OPTIONS]

Open (or create, if it does not exist yet) a new subfolder to an
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

This code is beta, version 1.3.19

=cut

1;
