
use strict;
package Mail::Box::MH;

use base 'Mail::Box';
our $VERSION = 2.00_17;

use Mail::Box::MH::Index;
use Mail::Box::MH::Message;
use Mail::Box::MH::Labels;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;
use Mail::Message::Head::Delayed;

use Carp;
use FileHandle;
use File::Copy;
use File::Spec;
use File::Basename;

=head1 NAME

Mail::Box::MH - Handle folders with a file per message.

=head1 CLASS HIERARCHY

 Mail::Box::MH
 is a Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::MH;
 my $folder = new Mail::Box::MH folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

This documentation describes how MH mailboxes work, and what you
can do with the MH folder object C<Mail::Box::MH>.
Please read C<Mail::Box-Overview> and C<Mail::Box> first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.  The working of MH-messages are
described in L<Mail::Box::MH::Message>.

=head1 METHOD INDEX

The general methods for C<Mail::Box::MH> objects:

   MB addMessage  MESSAGE               MR log [LEVEL [,STRINGS]]
   MB addMessages MESSAGE [, MESS...    MB message INDEX [,MESSAGE]
   MB allMessageIds                     MB messageId MESSAGE-ID [,MESS...
   MB close OPTIONS                     MB messages
   MB create FOLDERNAME [, OPTIONS]     MB modified [BOOLEAN]
   MB current [NUMBER|MESSAGE|MES...    MB name
   MB delete                               new OPTIONS
      directory                         MB openSubFolder NAME [,OPTIONS]
   MR errors                            MR report [LEVEL]
   MB find MESSAGE-ID                   MR reportAll [LEVEL]
   MB listSubFolders OPTIONS            MR trace [LEVEL]
   MB locker                            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MB DESTROY                           MR notImplemented
   MB appendMessages OPTIONS            MB organization
   MB clone OPTIONS                     MB read OPTIONS
   MB coerce MESSAGE                       readAllHeaders
   MB determineBodyType MESSAGE, ...       readMessageFilenames DIRECTORY
      folderToDirectory FOLDERNAM...    MB readMessages
   MB folderdir [DIR]                   MB scanForMessages MESSAGE, ME...
   MB foundIn [FOLDERNAME], OPTIONS     MB sort PREPARE, COMPARE, LIST
      highestMessageNumber              MB storeMessage MESSAGE
   MR inGlobalDestruction               MB timespan2seconds TIME
      index                             MB toBeThreaded MESSAGES
      labels                            MB toBeUnthreaded MESSAGES
   MR logPriority LEVEL                 MB write OPTIONS

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MB = L<Mail::Box>
   MR = L<Mail::Reporter>

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
 index_filename    Mail::Box::MH      foldername.'/.index'
 keep_index        Mail::Box::MH      0
 labels_filename   Mail::Box::MH      foldername.'/.mh_sequence'
 extract           Mail::Box          10kB
 lock_file         Mail::Box          foldername.'/.lock'
 lock_timeout      Mail::Box          3600    (1 hour)
 lock_wait         Mail::Box          10      (seconds)
 log               Mail::Reporter     'WARNINGS'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Box          <depends on folder location>

Only useful to write extension to C<Mail::Box::Mbox>.  Common users of
folders you will not specify these:

 OPTION            DEFINED BY         DEFAULT
 body_type         Mail::Box::MH      <see below>
 body_delayed_type Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options    Mail::Box          []
 head_type         Mail::Box          'Mail::Message::Head::Complete'
 head_delayed_type Mail::Box::MH      'Mail::Message::Head::Delayed'
 index             Mail::Box::MH      undef
 index_type        Mail::Box::MH      'Mail::Box::MH::Index'
 labels            Mail::Box::MH      undef
 labels_type       Mail::Box::MH      'Mail::Box::MH::Labels'
 locker            Mail::Box          undef
 lock_type         Mail::Box          'DOTLOCK'
 multipart_type    Mail::Box          'Mail::Message::Body::Multipart'
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::MH::Message'
 organization      Mail::Box          'DIRECTORY'
 realhead_type     Mail::Box          'Mail::Message::Head'

MH specific options:

=over 4

=item * keep_index =E<gt> BOOL

Keep an index file of the specified mailbox, one file per directory.
Using an index file will speed up things considerably, because it avoids
reading all the message files the moment that you open the folder.  When
you open a folder, you can use the index file to retrieve information such
as the subject of each message, instead of having to read possibly
thousands of messages.

=item * head_delayed_type =E<gt> CLASS

The headers which are delayed: which will be read from file when it
is needed, but not before.

=item * index_filename =E<gt> FILENAME

The FILENAME which is used in each directory to store the headers of all
mails. The filename shall not contain a directory path. (e.g. Do not use
C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>.)

=item * index =E<gt> OBJECT

You may specify an OBJECT of a type which extends C<Mail::Box::MH::Index>
(at least implements the C<get()> method), as alternative for an index file
reader as created by C<Mail::Box::MH>.

=item * labels_filename =E<gt> FILENAME

In MH-folders, messages can be labeled, for instance based on the
sender or whether it is read or not.  This status is kept in a
file which is usually called C<.mh_sequences>, but that name can
be overruled with this flag.

=item * labels =E<gt> OBJECT

You may specify an OBJECT of a type which extends C<Mail::Box::MH::Labels>
(at least implements the C<get()> method), as alternative for labels file
reader as created by C<Mail::Box::MH>.

=back

The C<body_type> options for Mbox folders defaults to:

 sub determine_body_type($$)
 {   my $head = shift;
     my $size = shift || 0;
     'Mail::Message::Body::' . ($size > 10000 ? 'File' : 'Lines');
 }

which will cause messages larger than 10kB to be stored in files, and
smaller files in memory.

=cut

my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.mh" : '.';

sub init($)
{   my ($self, $args) = @_;

    $args->{organization}  ||= 'DIRECTORY';
    $args->{folderdir}     ||= $default_folder_dir;

    $self->SUPER::init($args);

    my $directory            = $self->{MBM_directory}
       = (ref $self)->folderToDirectory($self->name, $self->folderdir);

    $self->{MBM_head_delayed_type}
        = $args->{head_delayed_type}  || 'Mail::Message::Head::Delayed';

    # About the index

    $self->{MBM_keep_index}  = $args->{keep_index} || 0;
    $self->{MBM_index}       = $args->{index};
    $self->{MBM_index_type}  = $args->{index_type} || 'Mail::Box::MH::Index';
    for($args->{index_filename})
    {  $self->{MBM_index_filename}
          = !defined $_ ? File::Spec->catfile($directory, '.index') # default
          : File::Spec->file_name_is_absolute($_) ? $_              # absolute
          :               File::Spec->catfile($directory, $_);      # relative
    }

    # About locking

    for($args->{lockfile} || undef)
    {   $self->locker->filename
          ( !defined $_ ? File::Spec->catfile($directory, '.index')  # default
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_)        # relative
          );
    }

    # About labels

    $self->{MBM_labels}      = $args->{labels};
    $self->{MBM_labels_type} = $args->{labels_type} || 'Mail::Box::MH::Labels';
    for($args->{labels_filename})
    {   $self->{MBM_labels_filename}
          = !defined $_ ? File::Spec->catfile($directory, '.mh_sequences')
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_);       # relative
    }

    # Check if we can write to the folder, if we need to.

    if($self->writeable && -e $directory && ! -w $directory)
    {   warn "Folder $directory is write-protected.\n";
        $self->{MB_access} = 'r';
    }

    $self;
}

#-------------------------------------------

=item directory

Returns the directory related to this folder.

Example:

    print $folder->directory;

=cut

sub directory() { shift->{MBM_directory} }

#-------------------------------------------

sub messageId($;$)
{   my ($self, $msgid) = (shift, shift);

    # Set or remove message-id
    if(@_)
    {   if(my $message = shift)
        {   # Define loaded message.
            $self->SUPER::messageId($msgid, $message);
            return $self->{MB_msgid}{$msgid};
        }
        else
        {   delete $self->{MB_msgid}{$msgid};
            return;
        }
    }

    # Message-id not found yet. Trigger autoload until the message-id appears.
    foreach my $message (reverse $self->messages)
    {   $message->head;
        last if exists $self->{MB_msgid}{$msgid};
    }

    $self->{MB_msgid}{$msgid};
}

sub messageID(@) {shift->messageId(@_)} # compatibility

#-------------------------------------------

sub allMessageIds() {shift->readAllHeaders->SUPER::allMessageIds }

#-------------------------------------------

sub create($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $directory = $class->folderToDirectory($name, $folderdir);

    return $class if -d $directory;
    unless(mkdir $directory, 0700)
    {   warn "Cannot create directory $directory: $!\n";
        return;
    }

    $class;
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

    my @dirs = grep { !/^\d+$|^\./ && -d File::Spec->catfile($dir,$_) && -r _ }
                   readdir DIR;

    closedir DIR;

    # Skip empty folders.  If a folder has sub-folders, then it is not
    # empty.
    if($args{skip_empty})
    {    my @not_empty;

         foreach my $subdir (@dirs)
         {   if(-f File::Spec->catfile($dir,$subdir, "1"))
             {   # Fast found: the first message of a filled folder.
                 push @not_empty, $subdir;
                 next;
             }

             opendir DIR, File::Spec->catfile($dir,$subdir) or next;
             my @entities = grep !/^\./, readdir DIR;
             closedir DIR;

             if(grep /^\d+$/, @entities)   # message 1 was not there, but
             {   push @not_empty, $subdir; # other message-numbers exist.
                 next;
             }

             foreach (@entities)
             {   next unless -d File::Spec->catfile($dir,$subdir,$_);
                 push @not_empty, $subdir;
                 last;
             }

         }

         @dirs = @not_empty;
    }

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};

    grep { $class->foundIn(File::Spec->catfile($dir,$_)) } @dirs;
}

#-------------------------------------------

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    my $dir = $self->directory . '/' . $name;

    unless(-d $dir || mkdir $dir, 0755)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->SUPER::openSubFolder(@_, folder => $self->name.'/'.$name);
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

    return 0 unless -d $directory;
    return 1 if -f File::Spec->catfile($directory, "1");

    # More thorough search required in case some numbered messages
    # disappeared (lost at fsck or copy?)

    return unless opendir DIR, $directory;
    foreach (readdir DIR)
    {   next unless m/^\d+$/;   # Look for filename which is a number.
        closedir DIR;
        return 1;
    }

    closedir DIR;
    0;
}

#-------------------------------------------

=item folderToDirectory FOLDERNAME, FOLDERDIR

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToDirectory($$)
{   my ($class, $name, $folderdir) = @_;
    $name =~ /^=(.*)/ ? File::Spec->catfile($folderdir,$1) : $name;
}

#-------------------------------------------

=item highestMessageNumber

Returns the highest number which is used in the folder to store a file.  This
method may be called when the folder is read (then this number can be
derived without file-system access), but also when the folder is not
read (yet).

=cut

sub highestMessageNumber()
{   my $self = shift;

    return $self->{MBM_highest_msgnr}
        if exists $self->{MBM_highest_msgnr};

    my $directory    = $self->directory;

    opendir DIR, $directory or return;
    my @messages = sort {$a <=> $b} grep /^\d+$/, readdir DIR;
    closedir DIR;

    $messages[-1];
}

#-------------------------------------------

=item index

Create a index reader/writer object.

=cut

sub index()
{   my $self  = shift;
    return () unless $self->{MBM_keep_index};

    $self->{MBM_index_type}->new
     ( filename  => $self->{MBM_index_filename}
     , head_wrap => $self->{MB_head_wrap}
     , $self->logSettings
     );
}

#-------------------------------------------

=item labels

Create a label reader/writer object.

=cut

sub labels()
{   my $self   = shift;
    $self->{MBM_labels_type}->new
     ( filename => $self->{MBM_labels_filename}
     , $self->logSettings
     );
}

#-------------------------------------------

=item readMessageFilenames DIRECTORY

Returns a list of all filenames which are found in this folder
directory and represent a message.  Message files are recognized
by having a number as name.

=cut

sub readMessageFilenames
{   my ($self, $dirname) = @_;

    opendir DIR, $dirname or return;
    my @msgnrs = sort {$a <=> $b}
                    grep /^\d+$/, readdir DIR;
    closedir DIR;

    grep { -f File::Spec->catfile($dirname,$_) && -r _ }
        @msgnrs;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    my $locker = $self->locker;
    $locker->lock or return;

    my @msgnrs = $self->readMessageFilenames($directory);

    my $index  = $self->{MBM_index};
    unless($index)
    {   $index = $self->index;
        $index->read if $index;
    }

    my $labels = $self->{MBM_labels};
    unless($labels)
    {    $labels = $self->labels;
         $labels->read if $labels;
    }

    foreach my $msgnr (@msgnrs)
    {
        my $msgfile = File::Spec->catfile($directory, $msgnr);
        my @log     = $self->logSettings;

        my $head;
        $head       = $index->get($msgfile) if $index;
        $head     ||= $self->{MBM_head_delayed_type}->new(@log);

        my $labref  = $labels ? $labels->get($msgnr) : undef;

        my $message = $args{message_type}->new
         ( head      => $head
         , labels    => $labref
         , filename  => $msgfile
         , folder    => $self
         );

        my $body    = $args{body_delayed_type}->new(@log, message => $message);
        $message->storeBody($body);

        $self->storeMessage($message) if $message;
    }

    $self->{MBM_highest_msgnr}  = $msgnrs[-1];

    # Which one becomes current?
    foreach ($self->messages)
    {   next unless $_->label('current') || 0;
        $self->current($_);
        last;
    }

    $self;
}
 
#-------------------------------------------

=item writeMessages [OPTIONS]

Write all messages to the folder-file.

 OPTION            DEFINED BY         DEFAULT
 force             Mail::Box          <true>
 head_wrap         Mail::Box          72
 keep_deleted      Mail::Box          <false>
 renumber          Mail::Box::MH      <true>
 save_deleted      Mail::Box          <false>

MH specific options:

=over 4

=item * renumber =E<gt> BOOL

Permit renumbering of message.  Bij default this is true, but for some
unknown reason, you may be thinking that messages should not be renumbered.

=back

=cut

sub writeMessages($)
{   my ($self, $args) = @_;

    # Write each message.  Two things complicate life:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $writer    = 0;

    my $locker    = $self->locker;
    unless($locker->lock)
    {   $self->log(ERROR => "Couldn't write without lock.");
        return;
    }

    my $renumber  = exists $args->{renumber} ? $args->{renumber} : 1;
    my $directory = $self->directory;
    my @messages  = @{$args->{messages}};

    foreach my $message (@messages)
    {
        my $filename = $message->filename;

        my $newfile;
        if($renumber || !$filename)
        {    $newfile = $directory . '/' . ++$writer;
        }
        else
        {    $newfile = $filename;
             $writer  = basename $filename;
        }

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

    # Write the labels- and the index-file.

    my $labels = $self->labels;
    $labels->write(@messages) if $labels;

    my $index  = $self->index;
    $index->write(@messages) if $index;

    $locker->unlock;

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

=item readAllHeaders

Force all messages to be read at least till their header information
is known.

=cut

sub readAllHeaders()
{   my $self = shift;
    my $nrmsgs = $self->messages;
    $self->readMessage($_, 0) foreach 0..$nrmsgs-1;
    $self;
}

#-------------------------------------------

sub appendMessages(@)
{   my $class  = shift;
    my %args   = @_;

    my @messages = exists $args{message} ? $args{message}
                 : exists $args{messages} ? @{$args{messages}}
                 : return ();

    my $self     = $class->new(@_, access => 'a');
    my $directory= $self->directory;
    return unless -d $directory;

    my $locker   = $self->locker;
    unless($locker->lock)
    {   $self->log(ERROR => "Cannot append message after $self without lock.");
        return;
    }

    my $msgnr    = $self->highestMessageNumber +1;

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
 
    my $labels   = $self->labels->append(@messages);

    $locker->unlock;
    $self->close;

    @messages;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

The explanation is complicated, but for normal use you should bother
yourself with all details.

=head2 How MH-folders work

MH-type folders use a directory to store the messages of one folder.  Each
message is stored in a seperate file.  This seems useful, because changes
in a folder change only a few of these small files, in contrast with
file-based folders where changes in a folder cause rewrites of huge
folder-files.

However, MH-based folders perform very bad if you need header-information
of all messages.  For instance, if you want to have full knowledge about
all message-threads (see C<Mail::Box::Thread::Manager>) in the folder, it
requires to read all header-lines in all message-files.  And usually, reading
your messages as threads is desired.

So, each message is written in a seperate file.  The file-names are
numbers, which count from C<1>.  Next to these message-files, a
directory may contain a file named C<.mh_sequences>, storing labels which
relate to the messages.  Furthermore, a folder-directory may contain
sub-directories, which are seen as sub-folders.

=head2 This implementation

This implementation supports the C<.mh-sequences> file and sub-folders.
Next to this, considerable effort it made to avoid reading each message-file.
This should boost performance of the C<Mail::Box> module over other
Perl-modules which are able to read folders.

Folder-types which store their messages each in one file, together in
one directory, are bad for performance.  Consider that you want to know
the subjects of all messages, while browser through a folder with your
mail-reading client.  This would cause all message-files to be read.

C<Mail::Box::MH> has two ways to try improve performance.  You can use
an index-file, and use on delay-loading.  The combination performs even
better.  Both are explained in the next sections.

=head2 An index-file

If you specify C<keep_index> as option to the folder creation method
C<new()>, then all header-lines of all messages from the folder which
have been read once, will also be written into one dedicated index-file
(one file per folder).  The default filename is C<.index>

However, index-files are not supported by any other reader which supports
MH (as far as I know).  If you read the folders with such I client, it
will not cause unrecoverable conflicts with this index-file, but at most
be bad for performance.

If you do not (want to) use an index-file, then delay-loading may
save your day.

=head2 Delayed loading

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
