
use strict;
package Mail::Box::File;
use base 'Mail::Box';

use Mail::Box::File::Message;

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
use IO::File ();

=head1 NAME

Mail::Box::File - handle file-based folders

=head1 SYNOPSIS

=head1 DESCRIPTION

Mail::Box::File is the base-class for all file-based folders: folders which
bundle multiple messages into one single file.  Usually, these messages are
separated by a special line which indicates the start of the next one.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=default folderdir $ENV{HOME}.'/Mail'
=default lock_file <foldername>.<lock-extension>

=default message_type 'Mail::Box::File::Message'

=option  lock_extension FILENAME|STRING
=default lock_extension '.lock'

When the dotlock locking mechanism is used, the lock is created with a
hardlink to the folder file.  For Mail::Box::File type of folders, this
file is by default named as the folder-file itself followed by
C<.lock>.  For example: the F<Mail/inbox> folder file will have a hardlink
made as F<Mail/inbox.lock>.

You may specify an absolute filename, a relative (to the folder's
directory) filename, or an extension (preceded by a dot).  So valid
examples are:

 .lock                  # appended to the folder's filename
 my_own_lockfile.test   # full filename, same dir
 /etc/passwd            # somewhere else

When the program runs with less priviledges (as normal user), often the
default inbox folder can not be locked with the lockfile name which is produced
by default.

=option  write_policy 'REPLACE'|'INPLACE'|undef
=default write_policy undef

Sets the default write policy (see write(policy)).  With C<undef>, the best
policy is autodetected.

=option  body_type CLASS|CODE
=default body_type <see description>

The C<body_type> option for File folders defaults to

 sub determine_body_type($$)
 {   my $head = shift;
     my $size = shift || 0;
     'Mail::Message::Body::' . ($size > 10000 ? 'File' : 'Lines');
 }

which will cause messages larger than 10kB to be stored in files, and
smaller files in memory.

=error Cannot get a lock on $type folder $self.

A lock is required to get access to the folder.  If no locking is needed,
specify the NONE lock type.

=warning Folder $name file $filename is write-protected.

The folder is opened writable or for appending (see new(access)), but the
operating system does not permit writing to the file.  The folder will be
opened read-only.

=cut

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';

sub _default_body_type($$)
{   my $size = shift->guessBodySize || 0;
    'Mail::Message::Body::'.($size > 10000 ? 'File' : 'Lines');
}

sub init($)
{   my ($self, $args) = @_;
    $args->{folderdir} ||= $default_folder_dir;
    $args->{body_type} ||= \&_default_body_type;
    $args->{lock_file} ||= '--';   # to be resolved later

    $self->SUPER::init($args);

    my $class = ref $self;

    my $filename         = $self->{MBF_filename}
       = $class->folderToFilename
           ( $self->name
           , $self->folderdir
           );

       if(-e $filename) {;}    # Folder already exists
    elsif(   $args->{create} && $class->create($args->{folder}, %$args)) {;}
    else
    {   $self->log(PROGRESS => "File $filename for folder $self does not exist.");
        return;
    }

    $self->{MBF_policy}  = $args->{write_policy};

    # Lock the folder.

    my $locker   = $self->locker;

    my $lockfile = $locker->filename;
    if($lockfile eq '--')            # filename to be used not resolved yet
    {   my $lockdir   = $filename;
        $lockdir      =~ s!/([^/]*)$!!;
        my $extension = $args->{lock_extension} || '.lock';

        $self->locker->filename
          ( File::Spec->file_name_is_absolute($extension) ? $extension
          : $extension =~ m!^\.!  ? "$filename$extension"
          :                         File::Spec->catfile($lockdir, $extension)
          );
    }

    unless($locker->lock)
    {   $self->log(ERROR => "Cannot get a lock on $class folder $self.");
        return;
    }

    # Check if we can write to the folder, if we need to.

    if($self->writable && ! -w $filename)
    {   $self->log(WARNING => "Folder $self file $filename is write-protected.");
        $self->{MB_access} = 'r';
    }

    # Start parser if reading is required.

      $self->{MB_access} !~ m/r/ ? $self
    : $self->parser              ? $self
    :                              undef;
}

#-------------------------------------------

=c_method create FOLDERNAME, OPTIONS

=error Cannot create directory $dir for folder $name.

While creating a file-organized folder, at most one level of directories
is created above it.  Apparently, more levels of directories are needed,
or the operating system does not allow you to create the directory.

=error Cannot create folder file $name: $!

The file-organized folder file cannot be created for the indicated reason.
In common cases, the operating system does not grant you write access to
the directory where the folder file should be stored.

=cut

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $subext    = $args{subfolder_extension};    # not always available
    my $filename  = $class->folderToFilename($name, $folderdir, $subext);

    return $class if -f $filename;

    my $dir       = dirname $filename;
    $class->log(ERROR => "Cannot create directory $dir for folder $name: $!"),return
        unless -d $dir || mkdir $dir, 0755;

    $class->dirToSubfolder($filename, $subext)
        if -d $filename && defined $subext;

    if(my $create = IO::File->new($filename, 'w'))
    {   $class->log(PROGRESS => "Created folder $name.");
        $create->close or return;
    }
    else
    {   $class->log(WARNING => "Cannot create folder file $name: $!\n");
        return;
    }

    $class;
}

#-------------------------------------------

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    $name   ||= $args{folder} or return;

    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $filename  = $class->folderToFilename($name, $folderdir);

    -f $filename;
}

#-------------------------------------------

=head2 Opening folders

=cut

#-------------------------------------------

sub organization() { 'FILE' }

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

=method filename

Returns the filename for this folder, which may be an absolute or relative
path to the file.

=examples

 print $folder->filename;

=cut

sub filename() { shift->{MBF_filename} }

#-------------------------------------------

sub close(@)
{   my $self = $_[0];            # be careful, we want to set the calling
    undef $_[0];                 #    ref to undef, as the SUPER does.
    shift;

    my $rc = $self->SUPER::close(@_);

    if(my $parser = delete $self->{MBF_parser}) { $parser->stop }

    $rc;
}

#-------------------------------------------

=head2 The messages

=cut

#-------------------------------------------

=head2 Sub-folders

=cut

#-------------------------------------------

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->openRelatedFolder(@_, folder => "$self/$name");
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method parser

Create a parser for this mailbox.  The parser stays alive as long as
the folder is open.

=cut

sub parser()
{   my $self = shift;

    return $self->{MBF_parser}
        if defined $self->{MBF_parser};

    my $source = $self->filename;

    my $mode = $self->{MB_access} || 'r';
    $mode    = 'r+' if $mode eq 'rw' || $mode eq 'a';

    my $parser = $self->{MBF_parser}
       = Mail::Box::Parser->new
        ( filename  => $source
        , mode      => $mode
        , trusted   => $self->{MB_trusted}
        , fix_header_errors => $self->{MB_fix_headers}
        , $self->logSettings
        ) or return;

    $parser->pushSeparator('From ');
    $parser;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $filename = $self->filename;

    # On a directory, simulate an empty folder with only subfolders.
    return $self if -d $filename;

    my @msgopts  =
     ( $self->logSettings
     , folder     => $self
     , head_type  => $args{head_type}
     , field_type => $args{field_type}
     , trusted    => $args{trusted}
     );

    my $parser   = $self->parser
       or return;

    while(1)
    {   my $message = $args{message_type}->new(@msgopts);
        last unless $message->readFromParser($parser);
        $self->storeMessage($message);
    }

    # Release the folder.
    $self;
}
 
#-------------------------------------------

=method write OPTIONS

=option  policy 'REPLACE'|'INPLACE'|undef
=default policy undef

In what way will the mail folder be updated.  If not specified during the
write, the value of the C<write_policy> at folder creation is taken.

Valid values:

=over 4

=item * C<REPLACE>

First a new folder is written in the same directory as the folder which has
to be updated, and then a call to move will throw away the old immediately
replacing it by the new.  The name of the folder's temporary file is
produced in tmpNewFolder().

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

=warning Cannot remove folder $name file $filename: $!

Writing an empty folder will usually remove that folder (see
new(remove_when_empty) to change that), but for the indicated reason
removal fails.

=error Unable to update folder $self.

When a folder is to be written, both replace and inplace write policies are
tried,  If both fail, the whole update fails.  You may see other, related,
error messages to indicate the real problem.

=error File too short to get write message $nr ($size, $need)

Mail::Box is lazy: it tries to leave messages in the folders until they
are used, which saves time and memory usage.  When this message appears,
something is terribly wrong: some lazy message are needed for updating the
folder, but they cannot be retreived from the original file anymore.  In
this case, messages can be lost.

This message does appear regularly on Windows systems when using the
'replace' write policy.  Please help to find the cause, probably something
to do with Windows incorrectly handling multiple filehandles open in the
same file.

=error Cannot replace $filename by $tempname, to update folder $name: $!

The replace policy wrote a new folder file to update the existing, but
was unable to give the final touch: replacing the old version of the
folder file for the indicated reason.

=cut

sub writeMessages($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    if( ! @{$args->{messages}} && $self->{MB_remove_empty})
    {   $self->log(WARNING => "Cannot remove folder $self file $filename: $!")
             unless unlink $filename;
        return $self;
    }

    my $policy = exists $args->{policy} ? $args->{policy} : $self->{MBF_policy};
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

    $self->parser->restart;
    $self;
}

sub _write_new($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $new      = IO::File->new($filename, 'w');
    return 0 unless defined $new;

    $_->write($new) foreach @{$args->{messages}};

    $new->close or return 0;

    $self->log(PROGRESS =>
                  "Wrote new folder $self with ".@{$args->{messages}}."msgs.");
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

    my $new      = IO::File->new($tmpnew, 'w')   or return 0;
    my $old      = IO::File->new($filename, 'r') or return 0;

    my ($reprint, $kept) = (0,0);

    foreach my $message ( @{$args->{messages}} )
    {
        my $newbegin = $new->tell;
        my $oldbegin = $message->fileLocation;

        if($message->isModified)
        {   $message->write($new);
            $message->moveLocation($newbegin - $oldbegin)
               if defined $oldbegin;
            $reprint++;
        }
        else
        {   my ($begin, $end) = $message->fileLocation;
            my $need = $end-$begin;

            $old->seek($begin, 0);
            my $whole;
            my $size = $old->read($whole, $need);

            $self->log(ERROR => "File too short to get write message "
                                . $message->seqnr. " ($size, $need)")
               unless $size == $need;

            $new->print($whole);
            $new->print("\n");

            $message->moveLocation($newbegin - $oldbegin);
            $kept++;
        }
    }

    my $ok = $new->close;
    return 0 unless $old->close && $ok;

    unlink $filename;
    unless(move $tmpnew, $filename)
    {   $self->log(WARNING =>
            "Cannot replace $filename by $tmpnew, to update folder $self: $!");

        unlink $tmpnew;
        return 0;
    }

    $self->log(PROGRESS => "Folder $self replaced ($kept, $reprint)");
    1;
}

# Inplace is currently very poorly implemented.  From the first
# location where changes appear, all messages are rewritten.

sub _write_inplace($)
{   my ($self, $args) = @_;

    my @messages = @{$args->{messages}};
    my $last;

    my ($msgnr, $kept) = (0, 0);
    while(@messages)
    {   my $next = $messages[0];
        last if $next->isModified || $next->seqnr!=$msgnr++;
        $last    = shift @messages;
        $kept++;
    }

    if(@messages==0 && $msgnr==$self->messages)
    {   $self->log(PROGRESS => "No changes to be written to $self.");
        return 1;
    }

    $_->body->load foreach @messages;

    my $mode     = $^O eq 'MSWin32' ? 'a' : '+<';
    my $filename = $self->filename;

    my $old      = IO::File->new($filename, $mode) or return 0;

    # Chop the folder after the messages which does not have to change.

    my $end = defined $last ? ($last->fileLocation)[1] : 0;
    unless($old->truncate($end))
    {   # truncate impossible: try replace writing
        $old->close;
        return 0;
    }

    unless(@messages)
    {   # All further messages only are flagged to be deleted
        $old->close or return 0;
        $self->log(PROGRESS => "Folder $self shortened in-place ($kept kept)");
        return 1;
    }

    # go to the end of the truncated output file.
    $old->seek(0, 2);

    # Print the messages which have to move.
    my $printed = @messages;
    foreach my $message (@messages)
    {   my $oldbegin = $message->fileLocation;
        my $newbegin = $old->tell;
        $message->write($old);
        $message->moveLocation($newbegin - $oldbegin);
    }

    $old->close or return 0;
    $self->log(PROGRESS => "Folder $self updated in-place ($kept, $printed)");
    1;
}

#-------------------------------------------

=c_method appendMessages OPTIONS

=error Cannot append messages to folder file $filename: $!

Appending messages to a not-opened file-organized folder may fail when the
operating system does not allow write access to the file at hand.

=cut

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages
      = exists $args{message}  ? $args{message}
      : exists $args{messages} ? @{$args{messages}}
      :                          return ();

    my $folder   = $class->new(lock_type => 'NONE', @_, access => 'w+')
       or return ();
 
    my $filename = $folder->filename;

    my $out      = IO::File->new($filename, 'a');
    unless($out)
    {   $class->log(ERROR => "Cannot append messages to folder file $filename: $!");
        return ();
    }

    my $msgtype = 'Mail::Box::File::Message';
    my @coerced;

    foreach my $msg (@messages)
    {   my $coerced
           = $msg->isa($msgtype) ? $msg
           : $msg->can('clone')  ? $msgtype->coerce($msg->clone)
           :                       $msgtype->coerce($msg);

        $coerced->write($out);
        push @coerced, $coerced;
    }

    my $ok = $folder->close;
    return 0 unless $out->close && $ok;

    @coerced;
}

#-------------------------------------------

=ci_method folderToFilename FOLDERNAME, FOLDERDIR, [SUBEXT]

Translate a folder name into a filename, using the
FOLDERDIR value to replace a leading C<=>.  SUBEXT is only used for MBOX
folders.

=cut

sub folderToFilename($$;$)
{   my ($thing, $name, $folderdir) = @_;

    substr $name, 0, 1, $folderdir
        if substr $name, 0, 1 eq '=';

    $name;
}

sub tmpNewFolder($) { shift->filename . '.tmp' }

#-------------------------------------------

=head1 IMPLEMENTATION

=head2 How file-based folders work

File-based folders store many messages in one file (let's call this a
`file-based' folder, in comparison to a `directory-based' folder types
like MH and Maildir).

=cut

1;
