
use strict;
package Mail::Box::Maildir;
use base 'Mail::Box::Dir';

use Mail::Box::Maildir::Message;

our $VERSION = 2.010;

use Carp;
use File::Copy;
use File::Spec;

=head1 NAME

Mail::Box::Maildir - handle Maildir folders

=head1 CLASS HIERARCHY

 Mail::Box::Maildir
 is a Mail::Box::Dir
 is a Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Maildir;
 my $folder = new Mail::Box::Maildir folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

This documentation describes how Maildir mailboxes work, and what you
can do with the Maildir folder object C<Mail::Box::Maildir>.
Please read C<Mail::Box-Overview> and C<Mail::Box::Dir> first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Box> (MB), L<Mail::Reporter> (MR), L<Mail::Box::Dir> (MBD).

The general methods for C<Mail::Box::Maildir> objects:

   MB AUTOLOAD                          MB locker
   MB addMessage  MESSAGE               MR log [LEVEL [,STRINGS]]
   MB addMessages MESSAGE [, MESS...    MB message INDEX [,MESSAGE]
   MB allMessageIds                     MB messageId MESSAGE-ID [,MESS...
   MB close OPTIONS                     MB messages
   MB create FOLDERNAME [, OPTIONS]     MB modified [BOOLEAN]
      createDirs FOLDERDIR              MB name
   MB current [NUMBER|MESSAGE|MES...       new OPTIONS
   MB delete                            MB openSubFolder NAME [,OPTIONS]
  MBD directory                         MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
   MB find MESSAGE-ID                   MR trace [LEVEL]
      folderIsEmpty FOLDERDIR           MR warnings
   MB listSubFolders OPTIONS            MB writeable

The extra methods for extension writers:

   MR AUTOLOAD                          MB organization
   MB DESTROY                           MB read OPTIONS
   MB appendMessages OPTIONS           MBD readAllHeaders
   MB clone OPTIONS                    MBD readMessageFilenames DIRECTORY
   MB coerce MESSAGE                    MB readMessages OPTIONS
   MB determineBodyType MESSAGE, ...    MB scanForMessages MESSAGE, ME...
  MBD folderToDirectory FOLDERNAM...    MB sort PREPARE, COMPARE, LIST
   MB folderdir [DIR]                   MB storeMessage MESSAGE
   MB foundIn [FOLDERNAME], OPTIONS     MB timespan2seconds TIME
   MR inGlobalDestruction               MB toBeThreaded MESSAGES
   MB lineSeparator [STRING|'CR'|...    MB toBeUnthreaded MESSAGES
   MR logPriority LEVEL                 MB update OPTIONS
   MR logSettings                       MB updateMessages OPTIONS
   MR notImplemented                    MB write OPTIONS

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new folder.  The are many options which are taken from other
objects.  For some, different options are set.  For MH-specific options
see below, but first the full list.

 OPTION            DEFINED BY         DEFAULT
 access            Mail::Box          'r'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          <no default>
 head_wrap         Mail::Box          72
 keep_dups         Mail::Box          0
 extract           Mail::Box          10kB
 lock_type         Mail::Box          'NONE'  # constant
 lock_file         Mail::Box          <not used>
 lock_timeout      Mail::Box          <not used>
 lock_wait         Mail::Box          <not used>
 log               Mail::Reporter     'WARNINGS'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Box          <depends on folder location>

Only useful to write extension to C<Mail::Box::MH>.  Common users of
folders you will not specify these:

 OPTION            DEFINED BY         DEFAULT
 body_type         Mail::Box::Dir     <see Mail::Box::Dir>
 body_delayed_type Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options    Mail::Box          []
 field_type        Mail::Box          undef
 head_type         Mail::Box          'Mail::Message::Head::Complete'
 head_delayed_type Mail::Box          'Mail::Message::Head::Delayed'
 locker            Mail::Box          <not used>
 multipart_type    Mail::Box          'Mail::Message::Body::Multipart'
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::MH::Message'
 realhead_type     Mail::Box          'Mail::Message::Head'

MH specific options:

=cut

my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.maildir" : '.';

sub init($)
{   my ($self, $args) = @_;

    croak "No locking possible for maildir folders."
       if exists $args->{locker}
       || (defined $args->{lock_type} && $args->{lock_type} ne 'NONE');

    $args->{lock_type}   = 'NONE';
    $args->{folderdir} ||= $default_folder_dir;

    $self->SUPER::init($args);

    $self;
}

#-------------------------------------------

=item createDirs FOLDERDIR

(Instance or class method)
The FOLDERDIR contains the absolute path of the location where the
messages are kept.  Maildir folders contain a C<tmp>, C<new>, and
C<cur> sub-directory within that folder directory as well.  This
method will ensure that all directories exist.
Returns false on failure.

=cut

sub createDirs($)
{   my ($thing, $dir) = @_;

    warn "Cannot create maildir folder directory $dir: $!\n", return
        unless -d $dir || mkdir $dir;

    my $tmp = File::Spec->catdir($dir, 'tmp');
    warn "Cannot create maildir folder subdir $tmp: $!\n", return
        unless -d $tmp || mkdir $tmp;

    my $new = File::Spec->catdir($dir, 'new');
    warn "Cannot create maildir folder subdir $new: $!\n", return
        unless -d $new || mkdir $new;

    my $cur = File::Spec->catdir($dir, 'cur');
    warn "Cannot create maildir folder subdir $cur: $!\n", return
        unless -d $cur || mkdir $cur;

    $thing;
}

#-------------------------------------------

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    $class->createDirs($directory) ? undef : $class;
}

#-------------------------------------------

=item folderIsEmpty FOLDERDIR

(Instance or class method)
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
        closdir DIR;

        return 0 if defined $first;
    }

    opendir DIR, $dir or return 1;
    while(my $entry = readdir DIR)
    {   next if $entry =~
           m/^(?:tmp|cur|new|\.qmail|bulletin(?:time|lock)|seriallock)$/;

        closedir DIR;
        return 0;
    }

    closedir DIR;
    1;
}

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

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    my $dir = $self->directory . '/' . $name;
    $self->createDirs(File::Spec->catfile($self->directory, $name));
    $self->openRelatedFolder(@_, folder => $dir);
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    -d File::Spec->catfile($directory, 'cur');
}

#-------------------------------------------

sub readMessageFilenames
{   my ($self, $dirname) = @_;

    opendir DIR, $dirname or return ();
    my @files = grep { m/^\d/ && -f File::Spec->catfile($dirname, $_) }
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

    my $curdir  = File::Spec->catfile($directory, 'cur');
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
         , @log
         );

        my $body    = $args{body_delayed_type}->new
         ( @log
         , message  => $message
         );

        $message->storeBody($body) if $body;
        $self->storeMessage($message);

        $message->statusToLabels->labelsToFilename;
        push @newmsgs, $message;
    }

    @newmsgs;
}

#-------------------------------------------

=item writeMessages [OPTIONS]

Write all messages to the folder-file.

 OPTION            DEFINED BY         DEFAULT
 force             Mail::Box          <true>
 head_wrap         Mail::Box          72
 keep_deleted      Mail::Box          <false>
 save_deleted      Mail::Box          <false>

=cut

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

    foreach my $message (@messages)
    {
        my $filename = $message->filename;

        my $newfile = $filename;

        if(!$filename)
        {   # New message for this folder.  Messages are only
            # added to the back, so shouldn't cause a problem.

            my $new = FileHandle->new($newfile, 'w') or die;
            $message->print($new);
            $new->close;
            $message->filename($newfile);
        }
        elsif($message->modified)
        {   # Write modified messages.
            my $oldtmp   = $filename . '.old';
            move $filename, $oldtmp;

            my $new = FileHandle->new($newfile, 'w') or die;
            $message->print($new);
            $new->close;

            unlink $oldtmp;
            $message->filename($newfile);
        }
        elsif($filename eq $newfile)
        {   # Nothing changed: content nor message-number.
        }
        else
        {   # Unmodified messages, but name changed.
            move $filename, $newfile;
            $message->filename($newfile);
        }
    }

    # Remove an empty folder.  This is done last, because the code before
    # in this method will have cleared the contents of the directory.

    if(!@messages && $self->{MB_remove_empty})
    {   # If something is still in the directory, this will fail, but I
        # don't mind.
        rmdir $directory;
    }

    $self;
}

#-------------------------------------------

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message}  ?   $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $self     = $class->new(@_, access => 'a');
    my $directory= $self->directory;
    return unless -d $directory;

    my $msgnr;
    foreach my $message (@messages)
    {
        my $filename = File::Spec->catfile($directory,$msgnr);

        if(my $new = FileHandle->new($filename, 'w'))
        {   $message->print($new);
            $message->filename($filename);
            $new->close;
        }
        else
        {   $self->log(ERROR =>
                "Unable to write message $msgnr to $filename: $!\n");
        }

        $msgnr++;
    }
 
    $self->close;

    @messages;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

The explanation is complicated, but for normal use you should bother
yourself with all details.

=head2 How Maildir-folders work

Maildir-type folders use a directory to store the messages of one folder.
Each message is stored in a seperate file.  This seems useful, because
changes in a folder change only a few of these small files, in contrast with
file-based folders where changes in a folder cause rewrites of huge
folder-files.

However, Maildir based folders perform very bad if you need header information
of all messages.  For instance, if you want to have full knowledge about
all message-threads (see C<Mail::Box::Thread::Manager>) in the folder, it
requires to read all header lines in all message files.  And usually, reading
your messages as threads is desired.  Maildir maintains a tiny amount
of info visible in the filename, which may make it perform just a little
bit faster than MH.

The following information was found at F<http://cr.yp.to/proto/maildir.html>.
Each message is written in a seperate file.  The filename is
constructed from the time-of-arrival, a unique component, hostname,
a syntax marker, and flags. For example C<1014220791.meteor.42:2,DF>.
The filename must match:

 my ($time, $unique, $hostname, $info)
    = $filename =~ m!^(\d+)\.(.*)\.(\w+)(\:.*)?$!;
 my ($semantics, $flags)
    = $info =~ m!([12])\,([RSTDF]+)$!;
 my @flags = split //, $flags;

The C<@flags> are sorted alphabetically, with the following meanings:

 D = draft, to be sent later
 F = flagged for user-defined purpose
 R = has been replied
 S = seen / (partially) read by the user
 T = trashed, flagged to be deleted later

=head2 Labels

The filename contains flags, and those flags are translated into labels
when the folder is opened.  Labels can be changed by the application using
the C<labels> method. 

Changes will directly reflect in a filename change.
The C<Status> and C<X-Status> lines in the header, which are used by
Mbox kind of folders, are ignored except when a new message is received
in the C<new> directory.  In case a message has to be written to file
for some reason, the status header lines are updated as well.

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.010.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
