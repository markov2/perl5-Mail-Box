
use strict;
use v5.6.0;

package Mail::Box::Mbox;
our @ISA     = 'Mail::Box';
our $VERSION = v0.6;

use Mail::Box;

use FileHandle;
use File::Copy;
use Fcntl qw(SEEK_END);

=head1 NAME

Mail::Box::Mbox - Handle folders with many messages per file.

=head1 SYNOPSIS

   use Mail::Box::Mbox;
   my $folder = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

This manual-page describes Mail::Box::Mbox and Mail::Box::Mbox::*
packages.  Read Mail::Box::Manager and Mail::Box first.

Handle file-based folders, where many messages are stored in one
file.

A File-based folder is a plain text-file where the start of a message
is detected by scanning for the word C<From >.  Lines which do accedentally
start with a C<From> are in the file preceeded by `>', however,
this is stripped when reading.

The name of a folder may be an absolute or relative path.  You can also
preceed the foldername by C<=>, which means that it is relative to the
I<folderdir> as specified at C<new>.

=head2 Message State Transition

The user of a folder gets it hand on a message-object, and is not bothered
with the actual data which is stored in the object at that moment.  As
implementor of a mail-package, you might be.

For trained eyes only:

   read()     !lazy
   -------> +----------------------------------> Mail::Box::
            |                                    MH::Message
            |                                         ^
            |                                         |
            |                    NotParsed    load    |
            |        ALL ,-----> NotReadHead ------>-'|
            | lazy      /                             |
            `--------->+                              |
                        \        NotParsed    load    |
                    REAL `-----> MIME::Head ------->-'


         ,-------------------------+---.
        |                      ALL |   | regexps && taken
        v                          |   |
   NotParsed    head()    get()   /   /
   NotReadHead --------> ------->+---'
             \          \         \
              \ other()  \ other() \regexps && !taken
               \          \         \
                \          \         \    load    Mail::Box::
                 `----->----+---------+---------> MBox::Message

         ,---------------.
        |                |
        v                |
   NotParsed     head()  |
   MIME::Head -------->--'
            \                           Mail::Box::
             `------------------------> MBox::Message


Terms: C<lazy> refers to the evaluation of the C<lazy_extract()> option. The
C<load> and C<load_head> are triggers to the C<AUTOLOAD> mothods.  All
terms like C<head()> refer to method-calls.  Finally, C<ALL>, C<REAL>,
and C<regexps> (default) refer to values of the C<take_headers> option
of C<new()>.

Hm... not that easy...  but relatively simple compared to MH-folder messages.

=head1 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  Many options are taken from object-classes which
Mail::Box::Mbox is an extention of.  Read below for a detailed
description of Mbox specific options.

 access            Mail::Box          'r'
 dummy_type        Mail::Box::Threads 'Mail::Box::Message::Dummy'
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          $ENV{HOME}.'/Mail'
 lazy_extract      Mail::Box          10kb
 lockfile          Mail::Box::Locker  foldername.lock-extention
 lock_extention    Mail::Box::Mbox    '.lock'
 lock_method       Mail::Box::Locker  'dotlock'
 lock_timeout      Mail::Box::Locker  1 hour
 lock_wait         Mail::Box::Locker  10 seconds
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::Mbox::Message'
 notreadhead_type  Mail::Box          'Mail::Box::Message::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::Mbox::Message::NotParsed'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 subfolder_extention Mail::Box::Mbox  '.d'
 take_headers      Mail::Box          <specify everything you need>
 <none>            Mail::Box::Tie

Mbox specific options:

=over 4

=item * lock_extention => FILENAME|STRING

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

=item * subfolder_extention => STRING

Mail folders which store their messages in files do usually not
support sub-folders, as known by mail folders which store messages
in a directory.

However, we simulate sub-directories if the user wants us to.  When
a subfolder of folder C<xyz> is created, we create a directory
which is called C<xyz.d> to contain them.  This extention C<.d>
can be changed using this option.

=back

=cut

my $default_folder_dir = $ENV{HOME} . '/Mail';

sub init($)
{   my ($self, $args) = @_;
    $args->{message_type}     ||= 'Mail::Box::Mbox::Message';
    $args->{dummy_type}       ||= 'Mail::Box::Message::Dummy';
    $args->{notreadhead_type} ||= 'Mail::Box::Message::NotReadHead';
    $args->{folderdir}        ||= $default_folder_dir;

    $self->SUPER::init($args);

    my $filename                = $self->{MB_filename}
       = (ref $self)->folderToFilename($self->name, $self->folderdir);

    $self->registerHeaders( qw/status x-status/ );

    $self->{MB_sub_ext}         = $args->{subfolder_extention} || '.d';

    my $lockdir  = $filename;
    $lockdir     =~ s!/([^/]*)$!!;
    my $extent   = $args->{lock_extention} || '.lock';
    $self->lockFilename
      ( $extent =~ m!^/!   ? $extent
      : $extent =~ m!^\.!  ? "$filename$extent"
      :                      "$lockdir/$extent"
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
            {   warn "Cannot create folder $filename.\n";
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
    $access = 'r+' if $access eq 'rw';

    unless($file = FileHandle->new($source, $access))
    {   warn "Where did the folder-file $self (file $source) go?\n";
        return;
    }

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

    delete $self->{MB_file};

    $self->unlock;
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
    my $file = $self->fileOpen or return;

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

    my ($begin, $end) = (0, undef);
    local $_;
    my $from_line  = $file->getline;

    while($from_line)
    {
        # Detect header.
        my @header;
        while(<$file>)
        {   last if /^\r?\n$/;
            push @header, $_;
        }
        last unless @header;

        # Detect body

        $end = $file->tell;
        my @body;

        while(<$file>)
        {   last if m/^From /;
            push @body, $_;
            $end = $file->tell;
        }

        # a pitty that an MIME::Entity does not split new and init...

        my $size    = $end - $begin;
        chomp $from_line;

        my @options =
          ( @{$self->{MB_message_opts}}
          , from         => $from_line
          , begin        => $begin
          , size         => $size
          );

        $from_line     = $_;               # catch for next message.
        $begin         = $end;             #

        my $message;
        if(not $self->lazyExtract(\@header, \@body, $size))
        {   #
            # Take the message immediately.
            #

            # Process all escapped from-lines.
            s/^\>(?=[fF]rom )// foreach @body;

            $message = $self->{MB_message_type}->new
              ( message => $parser->parse_data( [@header, "\n", @body] )
              , @options
              );
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

    $self->{MB_source_mtime}  = (stat $file)[9];
    $self->{MB_delayed_loads} = $delayed;

    $self->fileClose unless $delayed;
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
{   my Mail::Box::Mbox $self = shift;
    my $filename = $self->filename;
    my $tmpnew   = $self->tmpNewFolder($filename);

    my $was_open = $self->fileIsOpen;
    $self->fileOpen || return;  # for delayed messages.

    my $new = FileHandle->new($tmpnew, 'w');
    unless($new)
    {   warn "Unable to write to file $tmpnew for folder $self: $!\n";
        $self->fileClose;
        return 0;
    }

    $_->print($new) foreach $self->messages;

    $new->close;
    $self->fileClose unless $was_open;

    my $rc = move $tmpnew, $filename
       or warn "Could not replace $filename by $tmpnew, to update $self: $!\n";

    $rc;
}

#-------------------------------------------

=item addMessage MESSAGE

Add a message to the Mbox-folder.  If you specify a message with an
id which is already in the folder, the message will be ignored.

=cut

sub addMessage($)
{   my ($self, $message) = @_;
    $self->coerce($message);

    # Do not add the same message twice.
    my $msgid = $message->messageID;
    my $found = $self->messageID($msgid);
    return $self if $found && !$found->isDummy;

    # The message is accepted.
    $self->Mail::Box::addMessage($message);
    $self->messageID($msgid, $message);
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

    my $folder = $class->new(@_, access => 'a');
    $folder->lock;

    my $file   = $folder->fileOpen or return ();
    seek $file, 0, SEEK_END;

    $_->print($file) foreach @messages;

    $folder->fileClose;
    $folder->close;

    @messages;
}

#-------------------------------------------

=item filename

Returns the filename related to this folder.

Example:
    print $folder->filename;

=cut

sub filename() { shift->{MB_filename} }

#-------------------------------------------

=item folderToFilename FOLDERNAME ,FOLDERDIR

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToFilename($$)
{   my ($class, $name, $folderdir) = @_;
    $name =~ /^=(.*)/ ? "$folderdir/$1" : $name;
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

=item * folderdir => DIRECTORY

=back

Example:
   Mail::Box::Mbox->foundIn
      ( '=markov'
      , folderdir => "$ENV{HOME}/Mail"
      );

=cut

sub foundIn($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $default_folder_dir;
    my $filename  = $class->folderToFilename($name, $folderdir);
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
    my $dir             = defined $args{folderdir}
                        ? $args{folderdir}
                        : $default_folder_dir;

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    return () unless -d $dir && opendir DIR, $dir;

    # Some files have to be removed because they are created by all
    # kinds of programs, but are no folders.

    my @files = grep { ! m/.lock$/ && ! m/^\./ } readdir DIR;
    closedir DIR;

    # Look for files in the folderdir.  They should be readible to
    # avoid warnings for usage later.  Furthermore, if we check on
    # the size too, we avoid a syscall especially to get the size
    # of the file by performing that check immediately.

    @files = $args{skip_empty}
           ? grep { -f "$dir/$_" && -r _ && -s _ } @files
           : grep { -f "$dir/$_" && -r _ } @files;

    # Check if the files we want to return are really folders.

    $args{check}
    ? grep { $class->foundIn("$dir/$_") } @files
    : @files;
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
     ( folderdir => $self->filename . $self->{MB_sub_ext}
     , @_
     );
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
    my $extention = $self->{MB_sub_ext};
    my $dir       = $self->filename . $extention;

    unless(-d $dir || mkdir $dir)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->clone( folder => "$self$extention/$name", @_ );
}

###
### Mail::Box::Mbox::Message::Runtime
###

package Mail::Box::Mbox::Message::Runtime;
use Fcntl qw(SEEK_SET);

#-------------------------------------------

=back

=head1 Mail::Box::Mbox::Message::Runtime

This object contains methods which are part of as well delay-loaded
(not-parsed) as loaded messages, but not general for all folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in file-based folders use the following extra options for creation:

=over 4

=item * from LINE

The line which precedes each message in the file.  Some people detest
this line, but this is just how things were invented...

=back

=cut

my $unreg_msgid = time;

sub init($)
{   my ($self, $args) = @_;
    $self->{MBM_from_line} = $args->{from};
    $self->{MBM_begin}     = $args->{begin};

    unless(exists $args->{messageID})
    {   my $msgid = $self->head->get('message-id');
        $args->{messageID} = $1 if $msgid && $msgid =~ m/\<(.*?)\>/;
    }
    $self->{MBM_messageID} = $args->{messageID} || 'mbox-'.$unreg_msgid++;

    delete @$args{ qw/from begin/ };

    $self;
}

#-------------------------------------------

=item fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to produce
one.

When you pass a LINE, that this is stored.

=cut

sub fromLine(;$)
{   my $self = shift;

    return $self->{MBM_from_line} = shift if @_;

    return $self->{MBM_from_line} if $self->{MBM_from_line};

    # Create a fake.
    my $from   = $self->head->get('from') || '';
    my $sender = $from =~ m/\<.*?\>/ ? $1 : 'unknown';
    my $date   = $self->head->get('date') || '';
    $self->{MBM_from_line} = "From $sender $date\n";
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
    my $was_open = $folder->fileIsOpen;
    my $file     = $folder->fileOpen || return 0;

    if($self->modified)
    {   # Modified messages are printed as they were in memory.  This
        # may change the order and content of header-lines and (of
        # course) also the body.

        $self->createStatus->createXStatus;
        print $out $self->fromLine;
        $self->MIME::Entity::print($out);
        print $out "\n";
    }
    else
    {   # Unmodified messages are copied directly from their folder
        # file: fast and exact.
        my $size = $self->size;

        seek $file, $self->{MBM_begin}, SEEK_SET;

        my $msg;
        unless(defined read($file, $msg, $size))
        {   warn "Could not read $size bytes for message from $folder.\n";
            $folder->fileClose unless $was_open;
            return 0;
        }
        print $out $msg;
    }

    $folder->fileClose unless $was_open;
    1;
}

###
### Mail::Box::Mbox::Message
###

package Mail::Box::Mbox::Message;
our @ISA = qw(Mail::Box::Mbox::Message::Runtime Mail::Box::Message);

#-------------------------------------------

=back

=head1 Mail::Box::Mbox::Message

This object extends a Mail::Box::Message with extra tools and facts
on what is special to messages in file-based folders, with respect to
messages in other types of folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Message::init($args);
    $self->Mail::Box::Mbox::Message::Runtime::init($args);
    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE into a Mail::Box::Mbox::Message.  When
any message is offered to be stored in a mbox FOLDER, it first should have
all fields which are specific for Mbox-folders.

The coerced message is returned on success, else C<undef>.

Example:
   my $inbox = Mail::Box::Mbox->new(...);
   my $mh    = Mail::Box::MH::Message->new(...);
   Mail::Box::Mbox::Message->coerce($inbox, $mh);
   # Now, the $mh is ready to be included in $inbox.

However, you can better use
   $inbox->coerce($mh);
which will call the right coerce() for sure.

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
### Mail::Box::Mbox::Message::NotParsed
###

package Mail::Box::Mbox::Message::NotParsed;
our @ISA = qw/Mail::Box::Mbox::Message::Runtime
              Mail::Box::Message::NotParsed/;

use IO::InnerFile;

#-------------------------------------------

=back

=head1 Mail::Box::Mbox::Message::NotParsed

Not parsed messages stay in the file until the message is used.  Because
this folder structure uses many messages in the same file, the byte-locations
are remembered.

=head2 PUBLIC INTERFACE

=over 4

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::Mbox::Message::Runtime::init(@_);
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
    my $was_open = $folder->fileIsOpen;
    my $file     = $folder->fileOpen || return 0;
    my $if       = IO::InnerFile->new($file, $self->{MBM_begin}, $self->size)
                || return 0;

    $folder->fileClose unless $was_open;
    my $message = $folder->parser->parse($if);

    # A pitty that we have to copy data now...
    @$self{ keys %$message } = values %$message;

    my $args    = { message  => $message };

    $folder->{MB_delayed_loads}--;

    (bless $self, $class)->delayedInit($args);
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
