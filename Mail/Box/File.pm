
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

=method new OPTIONS

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
    {   $self->log(PROGRESS => "$class: Folder $filename does not exist.");
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
    {   $self->log(WARNING => "Couldn't get a lock on folder $self.");
        return;
    }

    # Check if we can write to the folder, if we need to.

    if($self->writable && ! -w $filename)
    {   $self->log(WARNING => "Folder $filename is write-protected.");
        $self->{MB_access} = 'r';
    }

    # Start parser if reading is required.

      $self->{MB_access} !~ m/r/ ? $self
    : $self->parser              ? $self
    :                              undef;
}

#-------------------------------------------

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $subext    = $args{subfolder_extension};    # not always available
    my $filename  = $class->folderToFilename($name, $folderdir, $subext);

    return $class if -f $filename;

    my $dir       = dirname $filename;
    $class->log(ERROR => "Cannot create directory $dir for $name."), return
        unless -d $dir || mkdir $dir, 0755;

    $class->dirToSubfolder($filename, $subext)
        if -d $filename && defined $subext;

    if(my $create = IO::File->new($filename, 'w'))
    {   $class->log(PROGRESS => "Created folder $name.");
        $create->close or return;
    }
    else
    {   $class->log(WARNING => "Cannot create folder $name: $!\n");
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

=cut

sub writeMessages($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    if( ! @{$args->{messages}} && $self->{MB_remove_empty})
    {   unless(unlink $filename)
        {   $self->log(WARNING =>
               "Couldn't remove folder $self (file $filename): $!");
        }
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
    $_->modified(0) foreach @{$args->{messages}};

    $self;
}

sub _write_new($)
{   my ($self, $args) = @_;

    my $filename = $self->filename;
    my $new      = IO::File->new($filename, 'w');
    return 0 unless defined $new;

    $_->print($new) foreach @{$args->{messages}};

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

        if($message->modified)
        {   $message->print($new);
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
            "Could not replace $filename by $tmpnew, to update $self: $!");

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

    my $mode     = $^O =~ m/^Win/i ? 'a' : '+<';
    my $filename = $self->filename;

    my $old      = IO::File->new($filename, $mode) or return 0;

    # Chop the folder after the messages which does not have to change.

    my $keepend  = $messages[0]->fileLocation;
    unless($old->truncate($keepend))
    {   $old->close;  # truncate impossible: try replace writing
        return 0;
    }
    $old->seek(0, 2);       # go to end

    # Print the messages which have to move.
    my $printed = @messages;
    foreach my $message (@messages)
    {   my $oldbegin = $message->fileLocation;
        my $newbegin = $old->tell;
        $message->print($old);
        $message->moveLocation($newbegin - $oldbegin);
    }

    $old->close or return 0;
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

    my $folder   = $class->new(lock_type => 'NONE', @_, access => 'w+')
       or return ();
 
    my $filename = $folder->filename;

    my $out      = IO::File->new($filename, 'a');
    unless($out)
    {   $class->log(ERROR => "Cannot append to $filename: $!");
        return ();
    }

    my $msgtype = 'Mail::Box::File::Message';
    my @coerced;

    foreach my $msg (@messages)
    {   my $coerced
           = $msg->isa($msgtype) ? $msg
           : $msg->can('clone')  ? $msgtype->coerce($msg->clone)
           :                       $msgtype->coerce($msg);

        $coerced->print($out);
        push @coerced, $coerced;
    }

    my $ok = $folder->close;
    return 0 unless $out->close && $ok;

    @coerced;
}

#-------------------------------------------

=method folderToFilename FOLDERNAME, FOLDERDIR, [SUBEXT]

(Class or instance method)  Translate a folder name into a filename, using the
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
