
use strict;
package Mail::Box::Maildir;
use base 'Mail::Box::Dir';

use Mail::Box::Maildir::Message;

use Carp;
use File::Copy;
use File::Spec;
use Sys::Hostname;

=chapter NAME

Mail::Box::Maildir - handle Maildir folders

=chapter SYNOPSIS

 use Mail::Box::Maildir;
 my $folder = new Mail::Box::Maildir folder => $ENV{MAIL}, ...;

=chapter DESCRIPTION

This documentation describes how Maildir mailboxes work, and what you
can do with the Maildir folder object C<Mail::Box::Maildir>.

Maildir is B<not supported for Windows>, because it create filenames
which are not accepted by the Windows system.

=chapter METHODS

=c_method new OPTIONS

=default folderdir    C<$ENV{HOME}/.maildir>
=default lock_type    C<'NONE'> (constant)
=default lock_file    <not used>
=default lock_timeout <not used>
=default lock_wait    <not used>

=cut

my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.maildir" : '.';

sub init($)
{   my ($self, $args) = @_;

    croak "No locking possible for maildir folders."
       if exists $args->{locker}
       || (defined $args->{lock_type} && $args->{lock_type} ne 'NONE');

    $args->{lock_type}   = 'NONE';
    $args->{folderdir} ||= $default_folder_dir;

    return undef
        unless $self->SUPER::init($args);

    $self;
}

#-------------------------------------------

=ci_method create FOLDERNAME, OPTIONS

=error Cannot create Maildir folder $name.

One or more of the directories required to administer a Maildir folder
could not be created.

=cut

sub create($@)
{   my ($thingy, $name, %args) = @_;
    my $class     = ref $thingy      || $thingy;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    if($class->createDirs($directory))
    {   $class->log(PROGRESS => "Created folder Maildir $name.");
        return $class;
    }
    else
    {   $class->log(ERROR => "Cannot create Maildir folder $name.");
        return undef;
    }
}

#-------------------------------------------

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    -d File::Spec->catdir($directory, 'cur');
}

#-------------------------------------------

sub type() {'maildir'}

#-------------------------------------------

sub listSubFolders(@)
{   my ($class, %args) = @_;
    my $dir;

    if(ref $class)
    {   $dir   = $class->directory;
        $class = ref $class;
    }
    else
    {   my $folder    = $args{folder}    || '=';
        my $folderdir = $args{folderdir} || $default_folder_dir;
        $dir   = $class->folderToDirectory($folder, $folderdir);
    }

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    # Read the directories from the directory, to find all folders
    # stored here.  Some directories have to be removed because they
    # are created by all kinds of programs, but are no folders.

    return () unless -d $dir && opendir DIR, $dir;

    my @dirs;
    while(my $d = readdir DIR)
    {   next if $d =~ m/^(new$|tmp$|cur$|\.)/;

        my $dir = File::Spec->catfile($dir,$d);
        push @dirs, $d if -d $dir && -r _;
    }

    closedir DIR;

    # Skip empty folders.

    @dirs = grep {!$class->folderIsEmpty(File::Spec->catfile($dir, $_))} @dirs
        if $args{skip_empty};

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};
    grep { $class->foundIn(File::Spec->catfile($dir,$_)) } @dirs;
}

#-------------------------------------------

sub nameOfSubFolder($)
{   my ($self, $name) = @_;
    File::Spec->catfile($self->directory, $name);
}

#-------------------------------------------

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->createDirs($self->nameOfSubFolder($name));
    $self->SUPER::openSubFolder($name, @_);
}

#-------------------------------------------

my $uniq = rand 1000;

=method coerce MESSAGE

=error Cannot create Maildir message file $new.

A message is converted from some other message format into a Maildir format
by writing it to a file with a name which contains the status flags of the
message.  Apparently, creating this file failed.

=cut

sub coerce($)
{   my ($self, $message) = @_;

    my $is_native = $message->isa('Mail::Box::Maildir::Message');
    my $coerced   = $self->SUPER::coerce($message);

    my $basename
      = $is_native
      ? (split m!/!, $message->filename)[-1]
      : $message->timestamp .'.'. hostname .'.'. $uniq++;

    my $dir = $self->directory;
    my $tmp = File::Spec->catfile($dir, tmp => $basename);
    my $new = File::Spec->catfile($dir, new => $basename);

    if($coerced->create($tmp) && $coerced->create($new))
         {$self->log(PROGRESS => "Added Maildir message in $new") }
    else {$self->log(ERROR    => "Cannot create Maildir message file $new.") }

    $coerced->labelsToFilename unless $is_native;
    $coerced;
}

#-------------------------------------------

=section Internals

=ci_method createDirs FOLDERDIR

The FOLDERDIR contains the absolute path of the location where the
messages are kept.  Maildir folders contain a C<tmp>, C<new>, and
C<cur> sub-directory within that folder directory as well.  This
method will ensure that all directories exist.
Returns false on failure.

=error Cannot create Maildir directory $dir: $!

A Maildir folder is represented by a directory, with some sub-directories.  The
top folder directory could not be created for the reason indicated.

=error Cannot create Maildir subdir $dir: $!

Each Maildir folder has three sub-directories for administration: C<new>,
C<tmp>, and C<cur>.  The mentioned directory could not be created for
the indicated reason.

=cut

sub createDirs($)
{   my ($thing, $dir) = @_;

    $thing->log(ERROR => "Cannot create Maildir folder directory $dir: $!\n"), return
        unless -d $dir || mkdir $dir;

    my $tmp = File::Spec->catdir($dir, 'tmp');
    $thing->log(ERROR => "Cannot create Maildir folder subdir $tmp: $!\n"), return
        unless -d $tmp || mkdir $tmp;

    my $new = File::Spec->catdir($dir, 'new');
    $thing->log(ERROR => "Cannot create Maildir folder subdir $new: $!\n"), return
        unless -d $new || mkdir $new;

    my $cur = File::Spec->catdir($dir, 'cur');
    $thing->log(ERROR =>  "Cannot create Maildir folder subdir $cur: $!\n"), return
        unless -d $cur || mkdir $cur;

    $thing;
}

#-------------------------------------------

=ci_method folderIsEmpty FOLDERDIR

Checks whether the folder whose directory is specified as absolute FOLDERDIR
is empty or not.  A folder is empty when the C<tmp>, C<new>, and C<cur>
subdirectories are empty and some files which are left there by application
programs.  The maildir spec explicitly states: C<.qmail>, C<bulletintime>,
C<bulletinlock> and C<seriallock>.  If any other files are found, the
directory is considered not-empty.

=cut

sub folderIsEmpty($)
{   my ($self, $dir) = @_;
    return 1 unless -d $dir;

    foreach (qw/tmp new cur/)
    {   my $subdir = File::Spec->catfile($dir, $_);
        next unless -d $subdir;

        opendir DIR, $subdir or return 0;
        my $first  = readdir DIR;
        closedir DIR;

        return 0 if defined $first;
    }

    opendir DIR, $dir or return 1;
    while(my $entry = readdir DIR)
    {   next if $entry =~
           m/^(?:tmp|cur|new|bulletin(?:time|lock)|seriallock|\..?)$/;

        closedir DIR;
        return 0;
    }

    closedir DIR;
    1;
}

#-------------------------------------------

sub readMessageFilenames
{   my ($self, $dirname) = @_;

    # Collect all files which start with a timestamp.  Ignore filenames
    # which end with '.new', because they are being created on this moment.

    opendir DIR, $dirname or return ();

    my @files
      = grep { /^\d/ && !/\.new$/ && -f File::Spec->catfile($dirname, $_) }
           readdir DIR;

    closedir DIR;

    # Sort the names.  Solve the Y2K (actually the 1 billion seconds
    # since 1970 bug) which hunts Maildir.  The timestamp, which is
    # the start of the filename will have some 0's in front, so each
    # timestamp has the same length.

    my %unified;
    m/^(\d+)/ and $unified{ ('0' x (9-length($1))).$_ } = $_ foreach @files;
    map { $unified{$_} } sort keys %unified;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    #
    # Read all accepted messages
    #

    my $curdir  = File::Spec->catdir($directory, 'cur');
    my @cur     = $self->readMessageFilenames($curdir);
    my @log     = $self->logSettings;

    foreach my $msgfile (@cur)
    {   my $msgpath = File::Spec->catfile($directory, cur => $msgfile);
        my $head    = $args{head_delayed_type}->new(@log);
        my $message = $args{message_type}->new
         ( head      => $head
         , filename  => $msgpath
         , folder    => $self
         );

        my $body    = $args{body_delayed_type}->new(@log, message => $message);
        $message->storeBody($body) if $body;
        $self->storeMessage($message);
    }

    $self->update;   # Get new messages
    $self;
}
 
#-------------------------------------------

sub updateMessages($)
{   my ($self, %args) = @_;
    my $directory = $self->directory;
    return unless -d $directory;

    my $newdir    = File::Spec->catfile($directory, 'new');
    my @new       = $self->readMessageFilenames($newdir);
    my @log       = $self->logSettings;

    my $msgtype   = $self->{MB_message_type};
    my @newmsgs;

    foreach my $newfile (@new)
    {    
        my $msgpath = File::Spec->catfile($directory, new => $newfile);
        my $head    = $args{head_delayed_type}->new(@log);
        my $message = $args{message_type}->new
         ( head     => $head
         , filename => $msgpath
         , folder   => $self
         , fix_header => $self->{MB_fix_headers}
         , @log
         );

        my $body    = $args{body_delayed_type}->new
         ( @log
         , message  => $message
         );

        $message->storeBody($body) if $body;
        $self->storeMessage($message);

        $message->labelsToFilename;
        push @newmsgs, $message->accept;
    }

    @newmsgs;
}

#-------------------------------------------

sub writeMessages($)
{   my ($self, $args) = @_;

    # Write each message.  Two things complicate life:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $writer    = 0;

    my $directory = $self->directory;
    my @messages  = @{$args->{messages}};

    my $tmpdir    = File::Spec->catfile($directory, 'tmp');
    die "Cannot create directory $tmpdir: $!"
        unless -d $tmpdir || mkdir $tmpdir;

    foreach my $message (@messages)
    {   next unless $message->isModified;

        my $filename = $message->filename;
        my $basename = (File::Spec->splitpath($filename))[2];

        my $newtmp   = File::Spec->catfile($directory, 'tmp', $basename);
        my $new      = IO::File->new($newtmp, 'w')
           or croak "Cannot create file $newtmp: $!";

        $message->write($new);
        $new->close;

        unlink $filename;
        move $newtmp, $filename
            or warn "Cannot move $newtmp to $filename: $!\n";
    }

    # Remove an empty folder.  This is done last, because the code before
    # in this method will have cleared the contents of the directory.

    if(!@messages && $self->{MB_remove_empty})
    {   # If something is still in the directory, this will fail, but I
        # don't mind.
        rmdir File::Spec->catfile($directory, 'cur');
        rmdir File::Spec->catfile($directory, 'tmp');
        rmdir File::Spec->catfile($directory, 'new');
        rmdir File::Spec->catfile($directory);
    }

    $self;
}

#-------------------------------------------

=c_method appendMessage OPTIONS

=error Cannot append Maildir message in $new to folder $self.

The message (or messages) could not be stored in the right directories
for the Maildir folder.

=cut

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message}  ?   $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $self     = $class->new(@_, access => 'a');
    my $directory= $self->directory;
    return unless -d $directory;

    my $tmpdir   = File::Spec->catfile($directory, 'tmp');
    croak "Cannot create directory $tmpdir: $!", return
        unless -d $tmpdir || mkdir $tmpdir;

    foreach my $message (@messages)
    {   my $is_native = $message->isa('Mail::Box::Maildir::Message');
        my $coerced   = $self->SUPER::coerce($message);

        my $basename
         = $is_native
         ? (split m!/!, $message->filename)[-1]
         : $message->timestamp .'.'. hostname .'.'. $uniq++;

       my $dir = $self->directory;
       my $tmp = File::Spec->catfile($dir, tmp => $basename);
       my $new = File::Spec->catfile($dir, new => $basename);

       if($coerced->create($tmp) && $coerced->create($new))
            {$self->log(PROGRESS => "Appended Maildir message in $new") }
       else {$self->log(ERROR    =>
                "Cannot append Maildir message in $new to folder $self.") }
    }
 
    $self->close;

    @messages;
}

#-------------------------------------------

=chapter DETAILS

The explanation is complicated, but for normal use you should bother
yourself with all details.

=section How MAILDIR folders work

Maildir-type folders use a directory to store the messages of one folder.
Each message is stored in a separate file.  This seems useful, because
changes in a folder change only a few of these small files, in contrast with
file-based folders where changes in a folder cause rewrites of huge
folder-files.

However, Maildir based folders perform very bad if you need header information
of all messages.  For instance, if you want to have full knowledge about
all message-threads (see M<Mail::Box::Thread::Manager>) in the folder, it
requires to read all header lines in all message files.  And usually, reading
your messages as threads is desired.  Maildir maintains a tiny amount
of info visible in the filename, which may make it perform just a little
bit faster than MH.


=cut

1;
