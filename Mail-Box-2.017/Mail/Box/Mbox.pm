
use strict;
package Mail::Box::Mbox;
use base 'Mail::Box';

our $VERSION = 2.017;

use Mail::Box::Mbox::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;

use Carp;
use File::Copy;
use File::Spec;
use File::Basename;
use POSIX ':unistd_h';
use IO::File;

=head1 NAME

Mail::Box::Mbox - handle folders in Mbox format

=head1 CLASS HIERARCHY

 Mail::Box::Mbox
 is a Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Mbox;
 my $folder = Mail::Box::Mbox->new(folder => $ENV{MAIL}, ...);

=head1 DESCRIPTION

This documentation describes how Mbox mailboxes work, and also describes
what you can do with the Mbox folder object C<Mail::Box::Mbox>.
Please read C<Mail::Box-Overview> and C<Mail::Box> first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.  The working of Mbox-messages are
described in L<Mail::Box::Mbox::Message>.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Box> (MB), L<Mail::Reporter> (MR).

The general methods for C<Mail::Box::Mbox> objects:

   MB addMessage  MESSAGE               MB message INDEX [,MESSAGE]
   MB addMessages MESSAGE [, MESS...    MB messageId MESSAGE-ID [,MESS...
   MB close OPTIONS                     MB messageIds
   MB copyTo FOLDER, OPTIONS            MB messages ['ALL',RANGE,'ACTI...
      create FOLDERNAME, ARGS           MB modified [BOOLEAN]
   MB current [NUMBER|MESSAGE|MES...    MB name
   MB delete                               new OPTIONS
   MR errors                            MB openSubFolder NAME [,OPTIONS]
      filename                          MR report [LEVEL]
   MB find MESSAGE-ID                   MR reportAll [LEVEL]
      listSubFolders [OPTIONS]          MR trace [LEVEL]
   MB locker                            MR warnings
   MR log [LEVEL [,STRINGS]]            MB writable

The extra methods for extension writers:

   MR AUTOLOAD                          MB organization
   MB DESTROY                              parser
   MB appendMessages OPTIONS            MB read OPTIONS
   MB clone OPTIONS                     MB readMessages OPTIONS
   MB coerce MESSAGE                    MB scanForMessages MESSAGE, ME...
   MB determineBodyType MESSAGE, ...    MB sort PREPARE, COMPARE, LIST
      folderToFilename FOLDERNAME...    MB storeMessage MESSAGE
   MB folderdir [DIR]                   MB timespan2seconds TIME
      foundIn [FOLDERNAME] [,OPTI...    MB toBeThreaded MESSAGES
   MR inGlobalDestruction               MB toBeUnthreaded MESSAGES
   MB lineSeparator [STRING|'CR'|...    MB update OPTIONS
   MR logPriority LEVEL                 MB updateMessages OPTIONS
   MR logSettings                          write OPTIONS
   MR notImplemented                    MB writeMessages
   MB openRelatedFolder OPTIONS

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new folder.  Many options are taken from object-classes to which
C<Mail::Box::Mbox> is an extension.  Read below for a detailed
description of Mbox specific options.

 OPTION              DESCRIBED IN       DEFAULT
 access              Mail::Box          'r'
 create              Mail::Box          0
 folder              Mail::Box          $ENV{MAIL}
 folderdir           Mail::Box          $ENV{HOME}.'/Mail'
 head_wrap           Mail::Box          72
 extract             Mail::Box          10kb
 keep_dups           Mail::Box          0
 lock_file           Mail::Box          foldername.lock-extension
 lock_extension      Mail::Box::Mbox    '.lock'
 lock_timeout        Mail::Box          1 hour
 lock_wait           Mail::Box          10 seconds
 log                 Mail::Reporter     'WARNINGS'
 write_policy        Mail::Box::Mbox    undef
 remove_when_empty   Mail::Box          1
 save_on_exit        Mail::Box          1
 subfolder_extension Mail::Box::Mbox    '.d'
 trace               Mail::Reporter     'WARNINGS'
 trusted             Mail::Box          <depends on folder location>

Only useful to write extension to C<Mail::Box::Mbox>.  Common users of
folders you will not specify these:

 OPTION              DEFINED BY         DEFAULT
 body_type           Mail::Box::Mbox    <see below>
 body_delayed_type   Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options      Mail::Box          []
 field_type          Mail::Box          undef
 head_type           Mail::Box          'Mail::Message::Head::Complete'
 head_delayed_type   Mail::Box          'Mail::Message::Head::Delayed'
 locker              Mail::Box          undef
 lock_type           Mail::Box          'DOTLOCK'
 multipart_type      Mail::Box          'Mail::Message::Body::Multipart'
 manager             Mail::Box          undef
 message_type        Mail::Box          'Mail::Box::Mbox::Message'

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

=item * write_policy =E<gt> 'REPLACE' || 'INPLACE'

Sets the default write policy.  See the C<policy> option to the
C<write()> method.

=back

The C<body_type> option for Mbox folders defaults to

   sub determine_body_type($$)
   {   my $head = shift;
       my $size = shift || 0;
       'Mail::Message::Body::' . ($size > 10000 ? 'File' : 'Lines');
   }

which will cause messages larger than 10kB to be stored in files, and
smaller files in memory.

=cut

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
my $default_extension  = '.d';

sub _default_body_type($$)
{   my $size = shift->guessBodySize || 0;
    'Mail::Message::Body::'.($size > 10000 ? 'File' : 'Lines');
}

sub init($)
{   my ($self, $args) = @_;
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{body_type}        ||= \&_default_body_type;

    $self->SUPER::init($args);

    my $sub_extension          = $self->{MBM_sub_ext}
       = $args->{subfolder_extension} || $default_extension;

    my $filename               = $self->{MB_filename}
       = (ref $self)->folderToFilename
           ( $self->name
           , $self->folderdir
           , $sub_extension
           );

    return unless -e $filename;

    $self->{MBM_policy}        = $args->{write_policy};

    my $lockdir   = $filename;
    $lockdir      =~ s!/([^/]*)$!!;
    my $extension = $args->{lock_extension} || '.lock';
    $self->locker->filename
      ( File::Spec->file_name_is_absolute($extension) ? $extension
      : $extension =~ m!^\.!  ? "$filename$extension"
      :                         File::Spec->catfile($lockdir, $extension)
      );

    # Check if we can write to the folder, if we need to.

    if($self->writable && ! -w $filename)
    {   $self->log(WARNING => "Folder $filename is write-protected.");
        $self->{MB_access} = 'r';
    }

    # Start parser if reading is required.

    return $self unless $self->{MB_access} =~ m/r/;
    $self->parser ? $self : undef;
}

#-------------------------------------------

sub head(;$)
{   my $self   = shift;
    return $self->head unless @_;

    my $head   = shift;
    $self->SUPER::head($head);
    $self->statusToLabels if $head;
    $head;
}

#-------------------------------------------

sub organization() { 'FILE' }

#-------------------------------------------

sub close(@)
{   my $self = $_[0];            # be careful, we want to set the calling
    undef $_[0];                 #    ref to undef, as the SUPER does.
    shift;

    $self->SUPER::close(@_);
}

#-------------------------------------------

=item filename

Returns the filename for this folder.

Example:

    print $folder->filename;

=cut

sub filename() { shift->{MB_filename} }


#-------------------------------------------

=item create FOLDERNAME, ARGS

 OPTION              DEFINED BY         DEFAULT
 folderdir           Mail::Box          <from object>
 subfolder_extension Mail::Box::Mbox    <from object>

Mbox specific options:

=over 4

=item * subfolder_extension =E<gt> STRING

=back

=cut

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    return $class if -f $filename;

    my $dir       = dirname $filename;
    $class->log(ERROR => "Cannot create directory $dir for $name"), return
        unless -d $dir || mkdir $dir, 0755;

    if(-d $filename)
    {   # sub-dir found, start simulating sub-folders.  The sub-folder dir
        # is moved to make place for this real folder.
        move $filename, $filename . $extension;
    }

    if(my $create = IO::File->new($filename, 'w'))
    {   $create->close;
    }
    else
    {   warn "Cannot create folder $name: $!\n";
        return;
    }

    $class;
}

#-------------------------------------------

=item listSubFolders [OPTIONS]

 OPTION              DEFINED BY         DEFAULT
 folder              Mail::Box          <obligatory>
 folderdir           Mail::Box          <from object>
 check               Mail::Box          <false>
 skip_empty          Mail::Box          <false>
 subfolder_extension Mail::Box::Mbox    <from object>

Mbox specific options:

=over 4

=item * subfolder_extension =E<gt> STRING

=back

=cut

sub listSubFolders(@)
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

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->openRelatedFolder(@_, folder => "$self/$name");
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item parser

Create a parser for this mailbox.  The parser stays alive as long as
some data from the folder still has to be parsed, and may be revived
when the information is to be written to a new file (or to update the
folder).

=cut

sub parser()
{   my $self = shift;

    return $self->{MBM_parser}
        if exists $self->{MBM_parser};

    my $source = $self->filename;

    my $access = $self->{MB_access} || 'r';
    $access = 'r+' if $access eq 'rw' || $access eq 'a';

    my $locker = $self->locker;
    unless($locker->lock)
    {   $self->log(WARNING =>
                   "Couldn't get a lock on folder $self (file $source)");
        return;
    }

    my $parser = $self->{MBM_parser}
       = Mail::Box::Parser->new
       ( filename  => $source
       , mode      => $access
       , trusted   => $self->{MB_trusted}
       , $self->logSettings
       ) or return;

    $parser->pushSeparator('From ');
    $parser;
}

#-------------------------------------------

sub parserClose()
{   my $self   = shift;
    my $parser = delete $self->{MBM_parser} or return;
    $parser->stop;    # but there may be more handles out-there which
                      # can start the parser again.

    $self->locker->unlock;
    $self;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $filename = $self->filename;

    # On a directory, simulate an empty folder with only subfolders.
    return $self if -d $filename;

    my $parser   = $self->parser or return;
    my $delayed  = 0;

    my @msgopts  =
      ( $self->logSettings
      , folder     => $self
      , head_wrap  => $args{head_wrap}
      , head_type  => $args{head_type}
      , field_type => $args{field_type}
      , trusted    => $args{trusted}
      );

    while(1)
    {   my $message = $args{message_type}->new(@msgopts);
        last unless $message->readFromParser($parser);
        $delayed++ if !$delayed && $message->isDelayed;
        $self->storeMessage($message);
    }

    # Release the folder.
    $self->parserClose unless $delayed;
    $self;
}
 
#-------------------------------------------

=item write OPTIONS

 OPTION            DEFINED BY         DEFAULT
 force             Mail::Box          <true>
 head_wrap         Mail::Box          72
 keep_deleted      Mail::Box          <false>
 save_deleted      Mail::Box          <false>
 policy            Mail::Box::Mbox    'REPLACE'|'INPLACE'

=over 4

=item policy =E<gt> 'REPLACE'|'INPLACE'|undef

In what way will the mail folder be updated.  If not specified during the
write, the value of the C<write_policy> at folder creation is taken.

Valid values:

=over 4

=item * C<REPLACE>

First a new folder is written in the same directory as the folder which has
to be updated, and then a call to move will throw away the old immediately
replacing it by the new.  The name of the folder's temporary file is
produced in C<tmpNewFolder>.

Writing in C<REPLACE> module is slightly optimized: messages which are not 
modified are copied from file to file, byte by byte.  This is much
faster than printing the data which is will be done for modified messages.

=item * C<INPLACE>

The original folder file will be opened read/write.  All message which where
not changed will be left untouched, until the first deleted or modified
message is detected.  All further messages are printed again.

=item * C<undef>

As default, or when C<undef> is explicitly specified, first C<REPLACE> mode
is tried.  Only when that fails, an C<INPLACE> update is performed.

=back

C<INPLACE> will be much faster than C<REPLACE> when applied on large
folders, however requires the C<truncate> function to be implemented on
your operating system.  It is also dangerous: when the program is interrupted
during the update process, the folder is corrupted.  Data may be lost.

However, in some cases it is not possible to write the folder with
C<REPLACE>.  For instance, the usual incoming mail folder on UNIX is
stored in a directory where a user can not write.  Of course, the
C<root> and C<mail> users can, but if you want to use this Perl module
with permission of a normal user, you can only get it to work in C<INPLACE>
mode.  Be warned that in this case folder locking via a lockfile is not
possible as well.

=back

=cut

sub writeMessages($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    if( ! @{$args->{messages}} && $self->{MB_remove_empty})
    {   unless(unlink $filename)
        {   $self->log(WARNING =>
               "Couldn't remove folder $self (file $filename): $!");
        }

        # Can the sub-folder directory be removed?  Don't mind if this
        # doesn't work (probably no subdir).
        rmdir $filename . $self->{MBM_sub_ext};

        return $self;
    }

    my $policy = exists $args->{policy} ? $args->{policy} : $self->{MBM_policy};
    $policy  ||= '';

    my $success
      = ! -e $filename       ? $self->_write_new($args)
      : $policy eq 'INPLACE' ? $self->_write_inplace($args)
      : $policy eq 'REPLACE' ? $self->_write_replace($args)
      : $self->_write_replace($args) ? 1
      : $self->_write_inplace($args);

    unless($success)
    {   $self->log(ERROR => "Unable to update folder $self.");
        return;
    }

    $self;
}


sub _write_new($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $new      = IO::File->new($filename, 'w');
    return 0 unless defined $new;

    my @messages = @{$args->{messages}};
    foreach my $message (@messages)
    {   my  $newbegin  = $new->tell;
        $message->print($new);
        $message->modified(0);
    }

    $self->log(PROGRESS => "Written new folder $self with ".@messages,"msgs.");
    $new->close;
    1;
}

# First write to a new file, then replace the source folder in one
# move.  This is much slower than inplace update, but it is safer,
# The folder is always in the right shape, even if the program is
# interrupted.

sub _write_replace($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $tmpnew   = $self->tmpNewFolder($filename);
    my $new      = IO::File->new($tmpnew, 'w');
    return 0 unless defined $new;
    return 0 unless open FILE, '<', $filename;

    my ($reprint, $kept) = (0,0);

    foreach my $message ( @{$args->{messages}} )
    {
        my $newbegin = $new->tell;
        my $oldbegin = $message->fileLocation;

        if($message->modified)
        {   $message->print($new);
            $message->modified(0);

            $message->moveLocation($newbegin - $oldbegin)
               if defined $oldbegin;
            $reprint++;
        }
        else
        {   my ($begin, $end) = $message->fileLocation;
            seek FILE, $begin, 0;
            my $whole;

            my $size = read FILE, $whole, $end-$begin;
            $self->log(ERROR => 'File too short to get write message.')
               if $size != $end-$begin;

            $new->print($whole);
            $message->moveLocation($newbegin - $oldbegin);
            $kept++;
        }
    }

    $new->close;
    CORE::close FILE;

    if(move $tmpnew, $filename)
    {    $self->log(PROGRESS => "Folder $self replaced ($kept, $reprint)");
    }
    else
    {   $self->log(WARNING =>
            "Could not replace $filename by $tmpnew, to update $self: $!");
        unlink $tmpnew;
    }

    1;
}

# Inplace is currently very poorly implemented.  From the first
# location where changes appear, all messages are rewritten.

sub _write_inplace($)
{   my ($self, $args) = @_;

    my @messages = @{$args->{messages}};

    my ($msgnr, $kept) = (0, 0);
    while(@messages)
    {   my $next = $messages[0];
        last if $next->modified || $next->seqnr!=$msgnr++;
        shift @messages;
        $kept++;
    }

    if(@messages==0 && $msgnr==$self->messages)
    {   $self->log(PROGRESS => "No changes to be written to $self.");
        return 1;
    }

    $_->body->load foreach @messages;
    $self->parserClose;

    my $mode     = $^O =~ m/^Win/i ? 'a' : '+<';
    my $filename = $self->filename;

    return 0 unless open FILE, $mode, $filename;

    # Chop the folder after the messages which do not have to change.
    my $keepend  = $messages[0]->fileLocation;
    unless(truncate FILE, $keepend)
    {   CORE::close FILE;  # truncate impossible: try replace writing
        return 0;
    }
    seek FILE, 0, 2;       # go to end

    # Print the messages which have to move.
    my $printed = @messages;
    foreach my $message (@messages)
    {   my $oldbegin = $message->fileLocation;
        my $newbegin = tell FILE;
        $message->print(\*FILE);
        $message->moveLocation($newbegin - $oldbegin);
    }

    CORE::close FILE;
    $self->log(PROGRESS => "Folder $self updated in-place ($kept, $printed)");

    1;
}

#-------------------------------------------

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages
      = exists $args{message}  ? $args{message}
      : exists $args{messages} ? @{$args{messages}}
      :                          return ();

    my $folder   = $class->new(@_, access => 'a');
    my $filename = $folder->filename;

    my $out      = IO::File->new($filename, 'a');
    unless($out)
    {   $class->log(ERROR => "Cannot append to $filename: $!");
        return ();
    }

    my $msgtype = 'Mail::Box::Mbox::Message';
    my @coerced;

    foreach my $msg (@messages)
    {   my $coerced
           = $msg->isa($msgtype) ? $msg
           : $msg->can('clone')  ? $msgtype->coerce($msg->clone)
           :                       $msgtype->coerce($msg);

        $coerced->print($out);
        push @coerced, $coerced;
    }

    $out->close;
    $folder->close;
    @coerced;
}

#-------------------------------------------

=item foundIn [FOLDERNAME] [,OPTIONS]

 OPTION              DEFINED BY         DEFAULT
 folder              Mail::Box::Mbox    undef
 folderdir           Mail::Box          <from object>
 subfolder_extension Mail::Box::Mbox    <from object>

If no FOLDERNAME is specified, then the C<folder> option is taken.

Mbox specific options:

=over 4

=item * folder =E<gt> FOLDERNAME

=item * subfolder_extension =E<gt> STRING

=back

=cut

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    $name   ||= $args{folder} or return;

    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $extension = $args{subfolder_extension} || $default_extension;
    my $filename  = $class->folderToFilename($name, $folderdir, $extension);

    if(-d $filename)      # fake empty folder, with sub-folders
    {   return 1 unless -f File::Spec->catfile($filename, '1')   # MH
                     || -d File::Spec->catdir($filename, 'cur'); # Maildir
    }

    return 0 unless -f $filename;
    return 1 if -z $filename;      # empty folder is ok

    my $file = IO::File->new($filename, 'r') or return 0;
    local $_;                      # Save external $_
    while(<$file>)
    {   next if /^\s*$/;
        $file->close;
        return m/^From /;
    }

    return 1;
}
#-------------------------------------------

=item folderToFilename FOLDERNAME, FOLDERDIR, EXTENSION

(Class method)  Translate a folder name into a filename, using the
FOLDERDIR value to replace a leading C<=>.

=cut

sub folderToFilename($$$)
{   my ($class, $name, $folderdir, $extension) = @_;
    return $name if File::Spec->file_name_is_absolute($name);

    my @parts = split m!/!, $name;
    my $real  = shift @parts;
    if(@parts)
    {   my $file  = pop @parts;

        $real = File::Spec->catdir($real.(-d $real ? '' : $extension), $_) 
           foreach @parts;

        $real = File::Spec->catfile($real.(-d $real ? '' : $extension), $file);
    }

    $real =~ s#^=#$folderdir/#;
    $real;
}

sub tmpNewFolder($) { shift->filename . '.tmp' }

#-------------------------------------------

sub scanForMessages(@) {shift}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head2 How Mbox folders work

Mbox folders store many messages in one file (let's call this a
`file-based' folder, in comparison to a `directory-based' folder types
like MH and Maildir).

In file-based folders, each message begins with a line which starts with
the string C<From >.  Lines inside a message which accidentally start with
C<From> are, in the file, preceeded by `E<gt>'. This character is stripped
when the message is read.

In this module, the name of a folder may be an absolute or relative path.
You can also preceed the foldername by C<=>, which means that it is
relative to the I<folderdir> option specified for the C<new> method.

=head2 Labels

Message labels (flags which tell about user-actions on the message) are
stored in C<Status> and C<X-Status> fields.  Each time a label is changed
(using the C<label()> method) these lines are updated immediately.

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

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
