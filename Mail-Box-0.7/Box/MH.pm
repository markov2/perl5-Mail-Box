
use strict;
use 5.006;

package Mail::Box::MH;
use Mail::Box;
use Mail::Box::Index;

our @ISA     = qw/Mail::Box Mail::Box::Index/;
our $VERSION = v0.7;

use Mail::Box;

use FileHandle;
use File::Copy;

=head1 NAME

Mail::Box::MH - Handle folders with a file per message.

=head1 SYNOPSIS

   use Mail::Box::MH;
   my $folder = new Mail::Box::MH folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

Mail::Box::MH extends Mail::Box and Mail::Box::Index to implement
MH-type folders.  This manual-page describes Mail::Box::MH and
Mail::Box::MH::* packages.  Read Mail::Box::Manager for the general
overview, Mail::Box for understanding mailboxes, and Mail::Box::Message
about how messages are used, first.

The explanation is complicated, but for normal use you should bother
yourself with all details.  Skip the manual-page to C<PUBLIC INTERFACE>.

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

=head2 Implementation

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
be read from the <.mh-sequences>.  But from the messages, only the
filenames are scanned.

Not before any header-line (or any other action on a message) is used,
the message is read.  This is done using Perl's AUTOLOADing, and is
transparent to users.  If the first thing you ask for is a header-line,
then C<lazy_extract> and C<take_headers> determine what how far this
message is parsed: into a Mail::Box::MH::NotParsed or a
Mail::Box::MH::Message.

The index-file is farmost best performing, but also in the second case,
performance can be ok.  When a mail-client opens a huge folder, only a few
of the messages will be displayed on the screen as folder-list.  Only from
the visible messages, header-lines like `Subject' are needed, so
the AUTOLOAD automatically reads those message-files.  Other messages
will only be read from file when they appear in the viewport.

=head2 Message State Transition

The user of a folder gets it hand on a message-object, and is not bothered
with the actual data which is stored in the object at that moment.  As
implementor of a mail-package, you might be.

For trained eyes only:

   read()     !lazy && !DELAY
   -------> +----------------------------------> Mail::Box::
            |                                    MH::Message
            | lazy && !DELAY && !index                ^
            +--------------.                          |
            |           \   \    NotParsed    load    |
            |            \   `-> NotReadHead ------>-'|
            |        REAL \                           |
            |              \                          |
            | index         v    NotParsed    load    |
            +------------------> MIME::Head ------->-'|
            |                       ^                 |
            |                       |                 |
            |                       |load_head        |
            |                       |                 |
            | DELAY && !index    NotParsed    load    |
            +------------------> <no head> -------->--'


         ,-------------------------+---.
        |                      ALL |   | regexps && taken
        v                          |   |
   NotParsed    head()    get()   /   /
   NotReadHead --------> ------->+---'
             \          \         \
              \ other()  \ other() \regexps && !taken
               \          \         \
                \          \         \    load    Mail::Box::
                 `----->----+---------+---------> MH::Message

         ,---------------.
        |                |
        v                |
   NotParsed     head()  |
   MIME::Head -------->--'
            \                           Mail::Box::
             `------------------------> MH::Message


                            load_head   NotParsed
                           ,----------> MIME::Head
                          /
   NotParsed    head()   / lazy
   <no head>  --------->+
                         \ !lazy
                          \
                           `-----------> Mail::Box::
                             load        MH::Message

Terms: C<lazy> refers to the evaluation of the C<lazy_extract()> option. The
C<load> and C<load_head> are triggers to the C<AUTOLOAD> mothods.  All
terms like C<head()> refer to method-calls.  The C<index> is true if there
is an index-file kept, and the message-header found in there seems still
valid (see the C<keep_index> option of C<new()>).

Finally, C<ALL>, C<REAL>, C<DELAY> (default), and C<regexps> refer to
values of the C<take_headers> option of C<new()>.  Notice that
C<take_headers> on C<DELAY> is more important than C<lazy_extract>.

Hm... not that easy...  Happily, the implementation takes fewer lines than
the documentation.

=head1 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  The are many options which are taken from other
objects.  For some, different options are set.  For MH-specific options
see below, but first the full list.

 access            Mail::Box          'r'
 dummy_type        Mail::Box::Threads 'Mail::Box::Message::Dummy'
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
 notreadhead_type  Mail::Box          'Mail::Box::Message::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::MH::Message::NotParsed'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 take_headers      Mail::Box          'DELAY'
 <none>            Mail::Box::Tie

MH specific options:

=over 4

=item * labels_filename => FILENAME

In MH-folders, messages can be labeled, for instance based on the
sender or whether it is read or not.  This status is kept in a
file which is usually called C<.mh_sequences>, but that name can
be overruled with this flag.

=back

=cut

my $default_folder_dir = "$ENV{HOME}/.mh";

sub init($)
{   my ($self, $args) = @_;

    $args->{message_type}     ||= 'Mail::Box::MH::Message';
    $args->{dummy_type}       ||= 'Mail::Box::Message::Dummy';
    $args->{notreadhead_type} ||= 'Mail::Box::Message::NotReadHead';
    $args->{keep_index}       ||= 0;
    $args->{folderdir}        ||= $default_folder_dir;
    $args->{take_headers}     ||= 'DELAY';

    $self->Mail::Box::init($args);

    my $dirname                 = $self->{MB_dirname}
       = (ref $self)->folderToDirname($self->name, $self->folderdir);

    for($args->{index_filename})
    {  $args->{index_filename}
          = !defined $_ ? "$dirname/.index"  # default
          : m!^/!       ? $_                 # absolute
          :               "$dirname/$_";     # relative
    }

    $self->Mail::Box::Index::init($args);

    for($args->{lockfile} || undef)
    {   $self->lockFilename
          ( !defined $_ ? "$dirname/.index"  # default
          : m!^/!       ? $_                 # absolute
          :               "$dirname/$_"      # relative
          );
    }

    for($args->{labels_filename})
    {   $self->labelsFilename
          ( !defined $_ ? "$dirname/.mh_sequences"  #default
          : m!^/!       ? $_                 # absolute
          :               "$dirname/$_"      # relative
          );
    }

    $self->registerHeaders( qw/status x-status/ );

    # Check if we can write to the folder, if we need to.

    if($self->writeable && ! -w $dirname)
    {   if(-e $dirname)
        {   warn "Folder $dirname is write-protected.\n";
            $self->{MB_access} = 'r';
        }
        elsif(!mkdir $dirname)
        {   warn "Couldnot create folder in $dirname.\n";
            return undef;
        }
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
    $self->lock;

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

    my $dirname    = $self->dirname;

    opendir DIR, $dirname or return;
    my @msgnrs = grep { -f "$dirname/$_" && -r _ }
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
        my $msgfile = "$dirname/$msgnr";
        my $head;

        $head       = $index{$msgfile}
            if exists $index{$msgfile} && -M $msgfile >= $index_age;

        my $size    = -s $msgfile;
        undef $head if $head && $head->get('x-mailbox-size') != $size;

        # First, we create a cheap structure, with minimal information.
        my $message = $self->{MB_notparsed_type}->new
          ( head       => $head
          , upgrade_to => $self->{MB_message_type}
          , filename   => $msgfile
          , size       => $size
          , msgnr      => $msgnr
          , labels     => $labels[$msgnr] || undef
          );

        $self->addMessage($message) if $message;
    }

    $self->{MB_source_mtime}   = (stat $dirname)[9];
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

    open MESSAGE, '<', $message->filename or return;

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

    $self->messageID($message->messageID, $message)
         ->statusToLabels->XstatusToLabels;
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
    }
    else
    {   $message->folder($self);
    }

    # The message is accepted.
    $self->Mail::Box::addMessage($message);
    $self;
}

#-------------------------------------------

=item write

Write all messages to the folder-file.  Returns whether this
was successful.  If you want to write to a different file, you
first create a new folder, then move the messages, and then write
that file.

=cut

sub writeMessages()
{   my $self     = shift;
    my @messages = $self->messages;

    $self->lock;

    # Write each message.  Two things complicate things:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $writer = 1;
    my %labeled;

    foreach my $message (@messages)
    {
        # Remove deleted messages.
        if($message->deleted)
        {   unlink $message->filename;
            next;
        }

        my $new      = $self->dirname . '/' . $writer;
        my $filename = $message->filename;

        if(!$filename)
        {   # New message for this folder.
            my $new = FileHandle->new($new, 'w') or die;
            $message->print($new);
            $new->close;
        }
        elsif($message->modified)
        {   # Write modified messages.
            my $oldtmp   = $filename . '.old';
            move($filename, $oldtmp);

            my $new = FileHandle->new($new, 'w') or die;
            $message->print($new);
            $new->close;

            unlink $oldtmp;
        }
        elsif($filename eq $new)
        {   # Nothing changed: content nor message-number.
        }
        else
        {   # Unmodified messages, but name changed.
            move($filename, $new);
        }

        # Collect the labels.
        my $labels = $message->labels;
        push @{$labeled{$_}}, $writer foreach keys %$labels;

        push @{$labeled{unseen}}, $writer
            unless $labels->{seen} || 0;

        $writer++;
    }

    #
    # Write the labels
    #

    $self->writeLabels(\%labeled);

    #
    # Write the index-file.
    #

    $self->writeIndex(@messages);
    $self->unlock;

    1;
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

=item appendMessages LIST-OF-OPTIONS

(Class method) Append one or more messages to this folder.  See
the manual-page of Mail::Box for explantion of the options.  The folder
will not be opened.  Returns the list of written messages on success.

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

    my $self   = $class->new(@_, access => 'a');
    $self->lock;

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
        my $new = FileHandle->new($self->dirname . '/' . $msgnr, 'w')
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

=item dirname

Returns the dirname related to this folder.

Example:
    print $folder->dirname;

=cut

sub dirname() { shift->{MB_dirname} }

#-------------------------------------------

=item folderToDirname FOLDERNAME, FOLDERDIR

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToDirname($$)
{   my ($class, $name, $folderdir) = @_;
    $name =~ /^=(.*)/ ? "$folderdir/$1" : $name;
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

    my $dirname    = $self->dirname;

    opendir DIR, $dirname or return;
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
{   my ($self, $msgid, $message) = @_;
    $self->Mail::Box::messageID($msgid, $message) if $message;

use Carp;
confess join(';', %$self), "\n" unless defined $self->{MB_last_untouched};

    # Trigger autoload until the message-id appears.
    $self->message($self->{MB_last_untouched}--)->head
       while $self->{MB_last_untouched} >= 0
          && !exists $self->{MB_msgid}{$msgid};

    return $self->{MB_msgid}{$msgid};
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

=over 4

=cut

#-------------------------------------------

=item labelsFilename [FILENAME]

Returns the filename of the dedicated file which contains the label
related to the messages in this folder-directory.

=back

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

    return unless open SEQ, '<', $seq;
    my @labels;

    local $_;
    while(<SEQ>)
    {   s/\s*\#.*$//;
        next unless length;
        my $label;

        next unless ($label) = s/^\s*(\w+)\s*\:\s*//;

        my $set = 1;
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

    my $seq      = FileHandle->new($filename, 'w') or return;
    my $oldout   = select $seq;

    print "# Generated by ",__PACKAGE__,"\n";

    local $" = ' ';
    foreach (sort keys %$labeled)
    {
        next if $_ eq 'seen';
        $_ = 'cur' if $_ eq 'current';

        print "$_:";
        my @msgs  = @{$labeled->{$_}};  #they are ordered already.
        while(@msgs)
        {   my $start = shift @msgs;
            my $end   = $start;

            $end = shift @msgs
                 while @msgs && $msgs[0]==$end+1;

            print $start==$end ? " $start" : " $start-$end";
        }
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

=item * folderdir => DIRECTORY

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
    my $dirname   = $class->folderToDirname($name, $folderdir);

    return 0 unless -d $dirname;
    return 1 if -f "$dirname/1";

    # More thorough search required in case some numbered messages
    # disappeared (lost at fsck or copy?)

    return unless opendir DIR, $dirname;
    foreach (readdir DIR)
    {   next unless m/^\d+$/;   # Look for filename which is a number.
        closedir DIR;
        return 1;
    }

    closedir DIR;
    0;
}

#-------------------------------------------

=item listFolders [OPTIONS]

List the folders in a certain directory.

=over 4

=item * folderdir => DIRECTORY

=item * check => BOOL

=item * skip_empty => BOOL

=back

=cut

sub listFolders(@)
{   my ($class, %args)  = @_;
    my $dir             = $args{folderdir} || $default_folder_dir;

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    # Read the directories from the directory, to find all folders
    # stored here.  Some directories have to be removed because they
    # are created by all kinds of programs, but are no folders.

    return () unless -d $dir && opendir DIR, $dir;

    my @dirs = grep { !/^\d+$|^\./ && -d "$dir/$_" && -r _ }
                   readdir DIR;

    closedir DIR;

    @dirs = grep { -f "$_/1" } @dirs
       if $args{skip_empty};

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};

    grep { $class->foundIn("$dir/$_") } @dirs;
}

#-------------------------------------------

=item subFolders [OPTIONS]

Returns the subfolders to a folder.  Although file-type folders do not
have a natural form of sub-folders, we can simulate them.  The
C<subfolder_extention> option of the constructor (C<new()>) defines
how sub-folders can be recognized.

=over 4

=item * check => BOOL

=item * skip_empty => BOOL

=back

=cut

sub subFolders(@)
{  my $self = shift;

   (ref $self)->listFolders
     ( folderdir => $self->dirname
     , @_
     );
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
    my $dir = $self->dirname . '/' . $name;

    unless(-d $dir || mkdir $dir)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->clone( folder => "$self/$name", @_ );
}

###
### Mail::Box::MH::Message::Runtime
###

package Mail::Box::MH::Message::Runtime;
use File::Copy;

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message::Runtime

This object contains methods which are part of as well delay-loaded
(not-parsed) as loaded messages, but not general for all folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in directory-based folders use the following extra options
for creation:

=over 4

=item * filename => FILENAME

The file where the message is stored in.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{MBM_filename}  = $args->{filename};
    $self;
}

my $unreg_msgid = time;

sub head_init()
{   my $self = shift;
    my $msgid = $self->head->get('message-id') || 'mh-'.$unreg_msgid++;
    $self->{MBM_messageID} = $msgid;
    $self;
}

#-------------------------------------------

=item print TO

Write one message to a file-handle.  Unmodified messages are taken
from the folder-file where they were stored in.  Modified messages
are written as in memory.  Specify a file-handle to write TO
(defaults to STDOUT).

=cut

sub print()
{   my $self     = shift;
    my $out      = shift || \*STDOUT;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    # Modified messages are printed as they were in memory.  This
    # may change the order and content of header-lines and (of
    # course) also the body.  If the message's original file
    # unexplainably disappeared, we also print the internally
    # stored message.

    if(!$self->modified && $filename && -r $filename)
    {   copy($filename, $out);
    }
    else
    {   $self->createStatus->createXStatus;
        $self->MIME::Entity::print($out);
    }

    1;
}

#-------------------------------------------

=item printIndex [FILEHANDLE]

Print the information of this message which is required to maintain
an index-file.  By default, this prints to STDOUT.

=cut

sub printIndex(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $head = $self->head;
    $head->add('X-MailBox-Filename', $self->filename);
    $head->print($out);
}

#-------------------------------------------

=item readIndex CLASS [,FILEHANDLE]

Read the headers of one message from the index into a CLASS
structure.  CLASS is (a sub-class of) a MIME::Head.  If no
FILEHANDLE is specified, the data is read from STDIN.

=cut

sub readIndex($;$)
{   my $self  = shift;
    shift->read(shift, shift || \*STDIN);
}

#-------------------------------------------

=item filename

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not read from a file.

=cut

sub filename() { shift->{MBM_filename} }

#-------------------------------------------

=item headIsRead

Checks if the head of the message is read.  This is true for fully
parsed messages and messages where the header was accessed once.

=cut

sub headIsRead()
{   my $self = shift;
    $self->isParsed || exists $self->{MBM_head};
}

###
### Mail::Box::MH::Message
###

package Mail::Box::MH::Message;
our @ISA = qw(Mail::Box::MH::Message::Runtime Mail::Box::Message);

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message

This object extends a Mail::Box::Message with extra tools and facts
on what is special to messages in file-based folders, with respect to
messages in other types of folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Message::init($args);
    $self->Mail::Box::MH::Message::Runtime::init($args);
    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method)
Coerce a MESSAGE into a Mail::Box::MH::Message, ready to be stored in
FOLDER.  When any message is offered to be stored in the mailbox, it
first should have all fields which are specific for MH-folders.

The coerced message is returned on success, else C<undef>.

Example:
   my $mh = Mail::Box::MH->new(...);
   my $message = Mail::Box::Mbox::Message->new(...);
   Mail::Box::MH::Message->coerce($mh, $message);
   # Now $message is ready to be stored in $mh.

However, you can better use
   $mh->coerce($message);
which will call coerce on the right message type for sure.

=cut

sub coerce($$)
{   my ($class, $folder, $message) = (shift, shift, shift);
    return $message if $message->isa($class);

    Mail::Box::Message->coerce($folder, $message, @_) or return;

    # When I know more what I can save from other types of messages, later,
    # that information will be extracted here, and transfered into arguments
    # for Runtime->init.

    (bless $message, $class)->Mail::Box::Mbox::Message::Runtime::init;
}


###
### Mail::Box::MH::Message::NotParsed
###

package Mail::Box::MH::Message::NotParsed;
our @ISA = qw/Mail::Box::MH::Message::Runtime
              Mail::Box::Message::NotParsed/;

use IO::InnerFile;

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message::NotParsed

Not parsed messages stay in the file until the message is used.  Because
this folder structure uses many messages in the same file, the byte-locations
are remembered.

=head2 PUBLIC INTERFACE

=over 4

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::MH::Message::Runtime::init(@_);
}

#-------------------------------------------

=item load CLASS [, ARRAY-OF-LINES]

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

If an array of lines is provided, that is parsed as message.  Otherwise,
the file of the message is opened and parsed.

=cut

sub load($;$)
{   my ($self, $class) = (shift, shift);

    my $folder = $self->folder;
    my $new;

    if(@_)
    {   $new = $folder->parser->parse_data(shift);
    }
    else
    {   my $filename = $self->filename;

        unless(open FILE, '<', $filename)
        {   warn "Cannot find folder $folder message $filename anymore.\n";
            return $self;
        }
        $new  =  $folder->parser->parse(\*FILE);
        close FILE;
    }

    my $args = { message => $new };
    $folder->{MB_delayed_loads}--;
    (bless $self, $class)->delayedInit($args);
}

#-------------------------------------------

=item head

Get the head of the message.  This may return immediately, because the
head is already read.  However, when we do not have a header yet, we
read the message.  At this moment, the C<lazy_extract> option of C<new>
comes into action: will we read the whole message now, or only the header?

=cut

sub head()
{   my $self = shift;
    return $self->{MBM_head} if exists $self->{MBM_head};
    $self->folder->readMessage($self->seqnr);
    $self->head;
}

#-------------------------------------------

=item messageID

Retreive the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

# This is the only method on a non-parsed object, which implicitly depends
# on a loaded header.  By checking the head, we know for sure that the
# header is loaded.

sub messageID(@)
{   my $self = shift;
    $self->head unless $self->{MBM_head};
    $self->Mail::Box::Message::messageID(@_);
}

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.6

=cut

1;
