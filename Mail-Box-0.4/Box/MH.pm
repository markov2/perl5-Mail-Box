
use strict;
use v5.6.0;

package Mail::Box::MH;
use Mail::Box;
use Mail::Box::Index;

our @ISA     = qw/Mail::Box Mail::Box::Index/;
our $VERSION = v0.4;

use Mail::Box;

use FileHandle;
use File::Copy;

=head1 NAME

Mail::Box::MH - Handle folders with a file per message.

=head1 SYNOPSIS

   use Mail::Box::MH;
   my $folder = new Mail::Box::MH folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

Mail::Box::MH extends Mail::Box and Mail::Box::Index to implements
MH-type folders.  This manual-page describes Mail::Box::MH and
Mail::Box::MH::* packages.  Read Mail::Box::Manager and Mail::Box first.

Handle file-based folders, where each folder is represented by a
directory, and each message by a file in that directory.  Messages
are numbered.

The name of a folder may be an absolute or relative path.  You can also
preceed the foldername by C<=>, which means that it is relative to the
I<folderdir> as specified at C<new>.

=head2 Delayed loading

Folder-types which store their messages each in one file, together in
one directory, are bad for performance.  Consider that you want to know
the subjects of all messages.

Mail::Box::MH has two ways to try improve performance.  If you specify
C<keep_index> as option to the folder creation method C<new()>, then
all header-lines of all messages will be written into the specified
index-file (one file per folder).

If you do not use an index-file, then the only thing what the opening
of a folder does is invertoring which message-files exists.  Nothing
else.  For any request to any message, that message will be
autoloaded.
If the first request is for a header-line, then only the header is parsed,
and the message still left in the file.  For anything else, the whole
message is parsed.

The index-file is farmost best performing, but also in the second case,
performance can be ok.  When you have opened a huge folder, only a few
of those folders will be presented on the screen as index.  To present
the index we need the subject, hence we need to load the header of these
messages.  When you scroll through the index, header after header is
parsed.
If you want to read you messages in threads, you have a serious
performance problem: threads can only be displayed if all message
headers were read.  In this case, you should use an index-file.

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
 lazy_extract      Mail::Box          10kb
 lockfile          Mail::Box::Locker  foldername.'/.lock'
 lock_method       Mail::Box::Locker  'dotlock'
 lock_timeout      Mail::Box::Locker  1 hour
 lock_wait         Mail::Box::Locker  10 seconds
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::MH::Message'
 notreadhead_type  Mail::Box          'Mail::Box::Message::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::MH::Message::NotParsed'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 take_headers      Mail::Box          <specify everything you need>
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

    if($args->{keep_index})
    {   $self->registerHeaders('REAL');
    }
    else
    {   $self->registerHeaders( qw/status x-status/ );
    }

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
        $expect = [ keys %$mode ];
        $mode   = 'SOME';
        $take   = '^(' . join('|', @$expect) . ')\:\s*(.*)$';
        $take_headers = qr/$take/i;
    }

    # Prepare the parser.

    my $parser     = $self->parser;
    my $delayed    = 0;

    # Select the messages from the directory (folder)
    # Each message is a file, where a sequence-number is
    # its name.

    my $dirname    = $self->dirname;

    opendir DIR, $dirname or return;
    my @messages = grep { -f "$dirname/$_" && -r _ }
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

    foreach my $msgnr (@messages)
    {
        my $msgfile = "$dirname/$msgnr";
        my $head;

        $head = $index{$msgfile}
            if exists $index{$msgfile} && -M $msgfile >= $index_age;

        my $size    = -s $msgfile;

        my @options =
          ( filename  => $msgfile
          , size      => $size
          , msgnr     => $msgnr
          , labels    => $labels[$msgnr] || undef
          );

        #
        # Read one message.
        #

        local $_;                       # protect global $_
        open MESSAGE, '<', $msgfile or return;

        # Read the header.

        my @header;
        local $_;
        while(<MESSAGE>)
        {   push @header, $_;
            last if /^\r?\n$/;
        }
        $self->unfoldHeaders(\@header);

        my $message;
        if(not $self->lazyExtract(\@header, undef, $size))
        {   #
            # Take the message immediately.
            #

            # Read the body, too.  For performance, this is added to the
            # header array.
            push @header, <MESSAGE>;

            $message = $self->{MB_message_type}->new
              ( message => $parser->parse_data(\@header)
              , @options
              );
        }
        elsif($mode eq 'SOME' || $mode eq 'ALL')
        {   #
            # Create delay-loaded message with some fields.
            #

            # Get all header lines for fast access.
            my $header = $self->{MB_notreadhead_type}->new(expect => $expect); 

            if($mode eq 'SOME')
            {   foreach (@header)
                {   $header->setField($1, $2) if $_ =~ $take_headers;
                }
            }
            else {  $header->setField(split ':', $_, 2) foreach @header }

            $message = $self->{MB_notparsed_type}->new
              ( head => $header
              , @options
              );

            $delayed++;
        }
        else
        {   #
            # Create a real header structure, but not yet the body.
            #

            $message = $self->{MB_notparsed_type}->new
              ( head => MIME::Head->new(\@header)->unfold
              , @options
              );

            $delayed++;
        }

        $message->statusToLabels->XstatusToLabels;
        $self->addMessage($message) if $message;

        close MESSAGE;
    }

    # Release the folder.

    $self->{MB_source_mtime}  = (stat $dirname)[9];
    $self->{MB_delayed_loads} = $delayed;
    $self->{MB_highest_msgnr} = $messages[-1];

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

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{MBM_filename}   = $args->{filename};
    $self->{MBM_msgnr}      = $args->{msgnr};
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

=item messageNr

Returns the number of the message as is used in its filename.  MH-folders
do put each message is a seperate file.  The files are numbers, but there
may some numbers missing.

=cut

sub messageNr() { shift->{MBM_msgnr} }


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

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::MH::Message::Runtime::init(@_);
}

#-------------------------------------------

=item load

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

=cut

sub load($)
{   my ($self, $class) = @_;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    unless(open FILE, '<', $filename)
    {   warn "Cannot find folder $folder message $filename anymore.\n";
        return $self;
    }

    my $message = $folder->parser->parse(\*FILE);
    $message->head->unfold;

    $folder->{MB_delayed_loads}--;

    my $args    = { message  => $message };

    # I try to pass the change on, back to the caller.  The calling
    # routine has a handle to the non-parsed message structure.  We
    # may succeed in replacing that by the next assignment.
    # When the tric fails, it costs some performance, because autoloading
    # will continue to be called.  However, in that method, the retry
    # is detected and will immediately returns the right object.

    $_[0]       = (bless $self, $class)->delayedInit($args);
}

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.4

=cut

1;
