
package Mail::Box::MH;

use Mail::Box;
use Mail::Box::Index;
use Mail::Box::MH::Message;

@ISA = qw/Mail::Box Mail::Box::Index/;

use strict;

use FileHandle;
use File::Copy;
use File::Spec;
use File::Basename;

=head1 NAME

Mail::Box::MH - Handle folders with a file per message.

=head1 SYNOPSIS

   use Mail::Box::MH;
   my $folder = new Mail::Box::MH folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

C<Mail::Box::MH> extends L<Mail::Box> and L<Mail::Box::Index> to implement
MH-type folders.  Read L<Mail::Box::Manager> for the general
overview, L<Mail::Box> for understanding mailboxes, and
L<Mail::Box::Message> about how messages are used, first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.  The working of MH-messages are
described in L<Mail::Box::MH::Message>.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  The are many options which are taken from other
objects.  For some, different options are set.  For MH-specific options
see below, but first the full list.

 access            Mail::Box          'r'
 create            Mail::Box          0
 dummy_type        Mail::Box::Threads 'Mail::Box::Thread::Dummy'
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          <no default>
 index_filename    Mail::Box::Index   foldername.'/.index'
 keep_index        Mail::Box::Index   0
 labels_filename   Mail::Box::MH      foldername.'/.mh_sequence'
 lazy_extract      Mail::Box          10000   (10kB)
 lockfile          Mail::Box::Locker  foldername.'/.lock'
 lock_method       Mail::Box::Locker  'dotlock'
 lock_timeout      Mail::Box::Locker  3600    (1 hour)
 lock_wait         Mail::Box::Locker  10      (seconds)
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::MH::Message'
 notreadhead_type  Mail::Box          'Mail::Box::MH::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::MH::NotParsed'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 take_headers      Mail::Box          'DELAY'
 thread_body       Mail::Box::Threads 0
 thread_timespan   Mail::Box::Threads '3 days'
 thread_window     Mail::Box::Threads 10
 <none>            Mail::Box::Tie

MH specific options:

=over 4

=item * labels_filename =E<gt> FILENAME

In MH-folders, messages can be labeled, for instance based on the
sender or whether it is read or not.  This status is kept in a
file which is usually called C<.mh_sequences>, but that name can
be overruled with this flag.

=back

=cut

my $default_folder_dir = exists $ENV{HOME} ?  "$ENV{HOME}/.mh" : '.';

sub init($)
{   my ($self, $args) = @_;

    $args->{notreadhead_type} ||= 'Mail::Box::NotReadHead';
    $args->{keep_index}       ||= 0;
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{take_headers}     ||= 'DELAY';

    $self->Mail::Box::init($args);

    my $directory                 = $self->{MB_directory}
       = (ref $self)->folderToDirectory($self->name, $self->folderdir);

    for($args->{index_filename})
    {  $args->{index_filename}
          = !defined $_ ? File::Spec->catfile($directory, '.index') # default
          : File::Spec->file_name_is_absolute($_) ? $_              # absolute
          :               File::Spec->catfile($directory, $_);      # relative
    }

    $self->Mail::Box::Index::init($args);

    for($args->{lockfile} || undef)
    {   $self->lockFilename
          ( !defined $_ ? File::Spec->catfile($directory, '.index')  # default
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_)        # relative
          );
    }

    for($args->{labels_filename})
    {   $self->labelsFilename
          ( !defined $_ ? File::Spec->catfile($directory, '.mh_sequences')
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_)        # relative
          );
    }

    $self->registerHeaders( qw/status x-status/ );

    # Check if we can write to the folder, if we need to.

    if($self->writeable && -e $directory && ! -w $directory)
    {   warn "Folder $directory is write-protected.\n";
        $self->{MB_access} = 'r';
    }

    $self;
}

#-------------------------------------------

=item readMessages

Read all messages from the folder.  This method is called at instantiation
of the folder, so do not call it yourself unless you have a very good
reason.

=cut

sub readMessages()
{   my $self = shift;

    my $directory = $self->directory;
    return unless -d $directory;

    $self->lock or return;

    # Prepare the labels.  The labels are related to the message-numbers,
    # but there may be some messages lacking (f.i. manually removed), which
    # means that after the reading, setting the labels would be harder.

    my @labels = $self->readLabels;

    # Prepare to scan for headers we want.  To speed things up, we create
    # a regular expression which will only fit exact on the right headers.
    # The only thing to do when the line fits is to lowercase the fieldname.

    my $mode = $self->registeredHeaders;
    my ($expect, $take, $take_headers);

    if(ref $mode)
    {   # If the user specified a list of fields, we prepare a regexp
        # which can match thid really fast.
        $self->{MB_expect}      = [ keys %$mode ];
        $mode   = 'SOME';
        $take   = '^(' . join('|', @$expect) . ')\:\s*(.*)$';
        $self->{MB_header_scan} = qr/$take/i;
    }

    $self->{MB_header_mode} = $mode;

    # Select the messages from the directory (folder)
    # Each message is a file, where a sequence-number is
    # its name.

    opendir DIR, $directory or return;
    my @msgnrs = grep { -f File::Spec->catfile($directory,$_) && -r _ }
                     sort {$a <=> $b}
                         grep /^\d+$/, readdir DIR;
    closedir DIR;

    # Retreive the information from the index-file if that
    # exists.  If so, this will speed-up things as lot.  We are
    # a bit anxious about changes to the folder which were made
    # by other programs or the user by hand.

    my @index     = $self->readIndex($self->{MB_realhead_type});
    my $index_age = -M $self->indexFilename if @index;
    my %index     = map { (scalar $_->get('x-mailbox-filename'), $_) } @index;

    foreach my $msgnr (@msgnrs)
    {
        my $msgfile = File::Spec->catfile($directory, $msgnr);
        my $head;

        $head       = $index{$msgfile}
            if exists $index{$msgfile} && -M $msgfile >= $index_age;

        my $size    = -s $msgfile;
        undef $head if $head && $head->get('x-mailbox-size') != $size;

        my @labels  = defined $labels[$msgnr] ? @{$labels[$msgnr]} : ();

        # First, we create a cheap structure, with minimal information.
        my $message = $self->{MB_notparsed_type}->new
          ( head       => $head
          , upgrade_to => $self->{MB_message_type}
          , filename   => $msgfile
          , size       => $size
          , msgnr      => $msgnr
          , labels     => [ seen => 1, @labels ]
          );

        $self->addMessage($message) if $message;
    }

    $self->{MB_source_mtime}   = (stat $directory)[9];
    $self->{MB_highest_msgnr}  = $msgnrs[-1];
    $self->{MB_delayed_loads}  = $#msgnrs;
    $self->{MB_last_untouched} = $#msgnrs;

    if($mode eq 'DELAY')
    {   # Delay everything.
    }
    elsif($mode eq 'SOME' || $mode eq 'REAL')
    {   # Trigger load of header, or whole.
        $self->readMessage($_) foreach 0..$#msgnrs;
    }

    # Which one becomes current?
    foreach ($self->allMessages)
    {   next unless $_->label('current') || 0;
        $self->current($_);
        last;
    }

    $self;
}
 
#-------------------------------------------

=item readMessage MESSAGE-NR [, BOOL]

Read one message from its file.  This method is automatically triggered
by the AUTOLOAD mechanism, so will usually not be called explicitly.

Although the name of the method seems to imply that also the message
body is read, this might not be true.  If BOOL is true (default false),
the body is certainly read.  Otherwise, it depends on the content of the
folder's C<take_headers> and C<lazy_extract> flags.
 
=cut

sub readMessage($;$)
{   my ($self, $msgnr, $force_read_all) = @_;
    my $message = $self->{MB_messages}[$msgnr];
    my $mode    = $self->{MB_header_mode};
    my $head    = $message->{MB_head};
    local $_;                       # protect global $_

    unless(open MESSAGE, $message->filename)
    {   warn "Unable to open ", $message->filename, ": $!\n";
        return;
    }

    # Read the header.
    my @header;
    while(<MESSAGE>)
    {   last if /^\r?\n$/;
        push @header, $_;
    }
    $self->unfoldHeaders(\@header);

    if($force_read_all || !$self->lazyExtract(\@header, undef, $message->size))
    {   # Take the message immediately.
        push @header, "\r\n", <MESSAGE>;
        $message->load($self->{MB_message_type}, \@header);
    }
    elsif($mode eq 'SOME' || $mode eq 'ALL')
    {   # Keep a delay-loaded message with some fields.
        my $header = $self->{MB_notreadhead_type}
                          ->new(expect => $self->{MB_expect}); 
        my $take_headers = $self->{MB_header_scan};

        if($mode eq 'SOME')
        {   foreach (@header)
            {   $header->setField($1, $2) if $_ =~ $take_headers;
            }
        }
        else {  $header->setField(split ':', $_, 2) foreach @header }

        $message->{MBM_head} = $header;
    }
    else
    {   # Create a real header structure, but not yet the body.
        $message->{MBM_head} = MIME::Head->new(\@header)->unfold;
    }

    close MESSAGE;

    --$self->{MB_last_untouched}
        if $message->seqnr == $self->{MB_last_untouched};

    $message->head_init;

    $self->messageID($message->messageID, $message);
    $self->toBeThreaded($message);
    $message->statusToLabels->XstatusToLabels;
    $message;
}

#-------------------------------------------

=item addMessage MESSAGE

Add a message to the MH-folder.

=cut

sub addMessage($)
{   my ($self, $message) = @_;

    $self->coerce($message);
    if($message->headIsRead)
    {   # Do not add the same message twice.
        my $msgid = $message->messageID;
        my $found = $self->messageID($msgid);
        return $self if $found && !$found->isDummy;

        $self->messageID($msgid, $message);
        $self->toBeThreaded($message);
    }
    else
    {   $message->folder($self);
    }

    # The message is accepted.
    $self->Mail::Box::addMessage($message);
    $self;
}

#-------------------------------------------

=item write [OPTIONS]

Write all messages to the folder-file.  Returns the folder when this
was successful.  As options you may specify (see C<Mail::Box>
for explanation)

=over 4

=item * keep_deleted =E<gt> BOOL

=item * save_deleted =E<gt> BOOL

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

    my $writer = 0;
    my %labeled;

    $self->lock;

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

        # Collect the labels.
        my $labels = $message->labels;
        foreach (keys %$labels)
        {   push @{$labeled{$_}}, $writer
                if $labels->{$_};
        }

        push @{$labeled{unseen}}, $writer
            unless $labels->{seen} || 0;
    }

    # Write the labels- and the index-file.

    $self->writeLabels(\%labeled);
    $self->writeIndex(@messages);
    $self->unlock;

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
is known.  The exact status reached depends on the C<take_headers>
of C<new()>, as described above.

=cut

sub readAllHeaders()
{   my $self = shift;
    my $nrmsgs = $self->allMessages;
    $self->readMessage($_, 0) foreach 0..$nrmsgs-1;
    $self;
}

#-------------------------------------------

=item appendMessages OPTIONS

(Class method) Append one or more messages to this folder.  The folder
will not be opened.

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

    my $self     = $class->new(@_, access => 'a');
    my $directory= $self->directory;
    return unless -d $directory;

    $self->lock or return;

    # Get labels from existing messages.
    my @labels  = $self->readLabels;
    my %labeled;
    for(my $msgnr = 1; $msgnr < @labels; $msgnr++)
    {   next unless defined $labels[$msgnr];
        push @{$labeled{$_}}, $msgnr foreach @{$labels[$msgnr]};
    }

    my $msgnr  = $self->highestMessageNumber +1;
    foreach my $message (@messages)
    {
        my $new = FileHandle->new(File::Spec->catfile($directory,$msgnr), 'w')
            or next;

        $message->print($new);
        $new->close;
        
        my $labels = $message->labels;
        push @{$labeled{$_}}, $msgnr foreach keys %$labels;

        push @{$labeled{unseen}}, $msgnr
            unless $labels->{seen} || 0;

        $msgnr++;
    }

    $self->writeLabels(\%labeled);
    $self->close;

    # We could update the message-index too, but for now, I just wait
    # until someone opens the folder: then the index will be updated
    # automatically.

    @messages;
}

#-------------------------------------------

=item directory

Returns the directory related to this folder.

Example:

    print $folder->directory;

=cut

sub directory() { shift->{MB_directory} }

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

    return $self->{MB_highest_msgnr}
        if exists $self->{MB_highest_msgnr};

    my $directory    = $self->directory;

    opendir DIR, $directory or return;
    my @messages = sort {$a <=> $b} grep /^\d+$/, readdir DIR;
    closedir DIR;

    $messages[-1];
}

#-------------------------------------------

=item messageID MESSAGE-ID [,MESSAGE]

Returns the message with the specified MESSAGE-ID.  If also a MESSAGE
is specified, the relationship between ID and MESSAGE will be stored
first.

Be warned, that if the message is not read at all (C<take_headers> set
to C<DELAY>), each message of the folder will be parsed, at least to get
its header.  The headers are read from back to front in the folder.

=cut

sub messageID($;$)
{   my ($self, $msgid) = (shift, shift);

    # Set or remove message-id
    if(@_)
    {   if(my $message = shift)
        {   # Define loaded message.
            $self->Mail::Box::messageID($msgid, $message);
            $self->toBeThreaded($message);
            return $self->{MB_msgid}{$msgid};
        }
        else
        {   delete $self->{MB_msgid}{$msgid};
            return;
        }
    }

    # Message-id not found yet.
    # Trigger autoload until the message-id appears.
    $self->message($self->{MB_last_untouched}--)->head
        while $self->{MB_last_untouched} >= 0
           && !exists $self->{MB_msgid}{$msgid};

    $self->{MB_msgid}{$msgid};
}

#-------------------------------------------

=item allMessageIDs

Returns a list of I<all> message-ids in the folder, including
those which are to be deleted.

Be warned that this will cause all message-headers to be read from
their files, if that was not done before.  This penalty can be
avoided keeping an index-file.  See the C<keep_index> option of
C<new()>.

=cut

sub allMessageIDs() { shift->readAllHeaders->Mail::Box::allMessageIDs }

#-------------------------------------------

=back

=head2 Manage message labels

MH-folder use one dedicated file per folder-directory to list special
tags to messages in the folder.  Typically, this file is called
C<.mh_sequences>.  The messages are numbered from C<1>.

Example content of C<.mh_sequences>:

   cur: 93
   unseen: 32 35-56 67-80

To generalize labels on messages, two are treated specially:

=over 4

=item * cur

The C<cur> specifies the number of the message where the user stopped
reading mail from this folder at last access.  Internally in these
modules refered to as label C<current>.

=item * unseen

With C<unseen> is listed which message was never read.
This must be a mistake in the design of MH: it must be a source of
confusion.  People should never use labels with a negation in the
name:

    if($seen)           if(!$unseen)    #yuk!
    if(!$seen)          if($unseen)
    unless($seen)       unless($unseen) #yuk!

So: label C<unseen> is translated into C<seen> for internal use.

=back

=over 4

=cut

#-------------------------------------------

=item labelsFilename [FILENAME]

Returns the filename of the dedicated file which contains the label
related to the messages in this folder-directory.

=cut

sub labelsFilename(;$)
{   my $self = shift;
    @_ ? $self->{MB_labelfile} = shift : $self->{MB_labelfile};
}

#-------------------------------------------

=item readLabels

In MH-folders, messages can be labeled to easily select sets which
are, for instance, posted by who.  The file is usually called
C<.mh_sequences> but that name can be overruled using the
C<labels_filename> option of C<new()>.

=cut

sub readLabels()
{   my $self = shift;
    my $seq  = $self->labelsFilename || return ();

    return unless open SEQ, $seq;
    my @labels;

    local $_;
    while(<SEQ>)
    {   s/\s*\#.*$//;
        next unless length;

        next unless s/^\s*(\w+)\s*\:\s*//;
        my $label = $1;

        my $set   = 1;
           if($label eq 'cur'   ) { $label = 'current' }
        elsif($label eq 'unseen') { $label = 'seen'; $set = 0 }

        foreach (split /\s+/)
        {   if( /^(\d+)\-(\d+)\s*$/ )
            {   push @{$labels[$_]}, $label, $set foreach $1..$2;
            }
            elsif( /^\d+\s*$/ )
            {   push @{$labels[$_]}, $label, $set;
            }
        }
    }

    close SEQ;
    @labels;
}

#-------------------------------------------

=item writeLabels HASH

Write the file which contains the relation between messages (actually
the messages' sequence-numbers) and the labels those messages have.
The parameter is a reference to an hash which contains for each
label a reference to a list of message-numbers which have to be
written.

=cut

sub writeLabels($)
{   my ($self, $labeled) = @_;
    my $filename = $self->labelsFilename || return;

    # Remove empty label-file.
    unless(keys %$labeled)
    {   unlink $filename;
        return $self;
    }

    my $seq      = FileHandle->new($filename, 'w') or return;
    my $oldout   = select $seq;

    local $" = ' ';
    foreach (sort keys %$labeled)
    {
        my @msgs  = @{$labeled->{$_}};  #they are ordered already.
        next if $_ eq 'seen';
        $_ = 'cur' if $_ eq 'current';
        print "$_:";

        while(@msgs)
        {   my $start = shift @msgs;
            my $end   = $start;

            $end = shift @msgs
                 while @msgs && $msgs[0]==$end+1;

            print $start==$end ? " $start" : " $start-$end";
        }
        print "\n";
    }

    select $oldout;
    $seq->close;
}

#-------------------------------------------

=back

=head2 folder management methods

Read the Mail::Box manual for more details and more options
on each method.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

Autodetect if there is a Mail::Box::MH folder specified here.  The
FOLDERNAME specifies the name of the folder, as is specified by the
application.  The OPTIONS is a list of extra parameters to the request.

For this class, we use (if defined):

=over 4

=item * folderdir =E<gt> DIRECTORY

=back

Example:

   Mail::Box::MH->foundIn
      ( '=markov'
      , folderdir => "$ENV{HOME}/.mh"
      );

=cut

sub foundIn($@)
{   my ($class, $name, %args) = @_;
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
    my $directory = $class->folderToDirectory($name, $folderdir);

    return $class if -d $directory;
    unless(mkdir $directory, 0700)
    {   warn "Cannot create directory $directory: $!\n";
        return;
    }

    $class;
}

#-------------------------------------------

=item listFolders [OPTIONS]

(Class and Instance method) List the folders in a certain directory.  As
class method, you will use the C<folder> option to indicate which folder
to list.  As instance method, the sub-folders of that folder are returned.

=over 4

=item * folder =E<gt> FOLDERNAME

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

=item * skip_empty =E<gt> BOOL

=back

=cut

sub listFolders(@)
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

=item openSubFolder NAME [,OPTIONS]

Open (or create, if it does not exist yet) a new subfolder to an
existing folder.

Example:

    my $folder = Mail::Box::MH->new(folder => '=Inbox');
    my $sub    = $folder->openSubFolder('read');
 
=cut

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    my $dir = $self->directory . '/' . $name;

    unless(-d $dir || mkdir $dir, 0755)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->clone( folder => File::Spec->catfile("$self",$name), @_ );
}

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
all message-threads (see Mail::Box::Threads) in the folder, it requires
to read all header-lines in all message-files.  And usually, reading in
threads is desired.

So, each message is written in a seperate file.  The file-names are
numbers, which count from C<1>.  Next to these message-files, a
directory may contain a file named C<.mh_sequences>, storing labels which
relate to the messages.  Furthermore, a folder-directory may contain
sub-directories, which are seen as sub-folders.

=head2 This implementation

This implementation supports the C<.mh-sequences> file and sub-folders.
Next to this, considerable effort it made to avoid reading each message-file.
This should boost performance of the Mail::Box module over other
Perl-modules which are able to read folders.

Folder-types which store their messages each in one file, together in
one directory, are bad for performance.  Consider that you want to know
the subjects of all messages, while browser through a folder with your
mail-reading client.  This would cause all message-files to be read.

Mail::Box::MH has two ways to try improve performance.  You can use
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

The delay-loading mechanism of messages tries to be as lazy as possible.
When the folder is opened, none of the message-files will be read.  If
there is an index-file, those headers will be taken.  The labels will
be read from the C<.mh-sequences>.  But from the messages, only the
filenames are scanned.

Not before any header-line (or any other action on a message) is used,
the message is read.  This is done using Perl's AUTOLOADing, and is
transparent to users.  If the first thing you ask for is a header-line,
then C<lazy_extract> and C<take_headers> determine what how far this
message is parsed: into a C<Mail::Box::MH::NotParsed> or a
C<Mail::Box::MH::Message>.

The index-file is farmost best performing, but also in the second case,
performance can be ok.  When a mail-client opens a huge folder, only a few
of the messages will be displayed on the screen as folder-list.  Only from
the visible messages, header-lines like `Subject' are needed, so
the AUTOLOAD automatically reads those message-files.  Other messages
will only be read from file when they appear in the viewport.

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.001

=cut

1;
