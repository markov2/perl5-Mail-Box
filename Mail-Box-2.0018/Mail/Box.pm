
use strict;
use warnings;

package Mail::Box;
use base 'Mail::Reporter';

use Mail::Box::Message;
use Mail::Box::Locker;

our $VERSION = 2.00_18;

use Carp;
use Scalar::Util 'weaken';

use overload '@{}' => sub { shift->{MB_messages} }
           , '""'  => 'name'
           , 'cmp' => sub {$_[0]->name cmp "${_[1]}"};

#-------------------------------------------
# Clean exist required to remove lockfiles and to save changes.

$SIG{INT} = $SIG{QUIT} = $SIG{PIPE} = $SIG{TERM} = sub {exit 0};

#-------------------------------------------

=head1 NAME

Mail::Box - Manage a message-folder.

=head1 CLASS HIERARCHY

 Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open(folder => $ENV{MAIL}, ...);
 print $folder->name;

 # Get the first message.
 print $folder->message(0);

 # Delete the third message
 $folder->message(3)->delete;

 # Get the number of undeleted messages in scalar context.
 my $emails = $folder->messages;

 # Iterate over the messages.
 foreach ($folder->messages) {...}     # all messages
 foreach (@$folder) {...}              # all messages

 $folder->addMessage(new Mail::Box::Message(...));

Tied-interface:   (See C<Mail::Box::Tie>)

 tie my(@inbox), 'Mail::Box::Tie::ARRAY', $inbox;
 $inbox[3]->print        # same as $folder->message(3)->print

 tie my(%inbox), 'Mail::Box::Tie::HASH', $inbox;
 $inbox{$msgid}->print   # same as $folder->messageId($msgid)->print


=head1 DESCRIPTION

A C<Mail::Box::Manager> creates C<Mail::Box> objects.  But you already
knew, because you started with the C<Mail::Box-Overview> manual page.
That is obligatory reading, sorry!

C<Mail::Box> is the base-class for accessing various types of mail-folder
organizational structures in a uniform way.  The various folder types vary
on how they store their messages. For example, a folder may store many
messages in a single file, or store each message in a separate file in a
directory. Similarly, there may be different techniques for locking the
folders.

The C<Mail::Box> is used to get C<Mail::Box::Message> objects from the
mailbox.  Applications then usually use information or add information to the
message object. For instance, the application can set a flag which indicates
whether a message has been replied to or not. In addition, applications can
extend C<Mail::Box::Message> by deriving from it. See C<Mail::Box::Message>
and its derived classes for more information.

=head1 METHOD INDEX

The general methods for C<Mail::Box> objects:

      addMessage  MESSAGE                  message INDEX [,MESSAGE]
      addMessages MESSAGE [, MESS...       messageId MESSAGE-ID [,MESS...
      allMessageIds                        messages
      close OPTIONS                        modified [BOOLEAN]
      create FOLDERNAME [, OPTIONS]        name
      current [NUMBER|MESSAGE|MES...       new OPTIONS
      delete                               openSubFolder NAME [,OPTIONS]
   MR errors                            MR report [LEVEL]
      find MESSAGE-ID                   MR reportAll [LEVEL]
      listSubFolders OPTIONS            MR trace [LEVEL]
      locker                            MR warnings
   MR log [LEVEL [,STRINGS]]               writeable

The extra methods for extension writers:

   MR AUTOLOAD                          MR notImplemented
      DESTROY                              organization
      appendMessages OPTIONS               read OPTIONS
      clone OPTIONS                        readMessages
      coerce MESSAGE                       scanForMessages MESSAGE, ME...
      determineBodyType MESSAGE, ...       sort PREPARE, COMPARE, LIST
      folderdir [DIR]                      storeMessage MESSAGE
      foundIn [FOLDERNAME], OPTIONS        timespan2seconds TIME
   MR inGlobalDestruction                  toBeThreaded MESSAGES
   MR logPriority LEVEL                    toBeUnthreaded MESSAGES
   MR logSettings                          write OPTIONS

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=item new OPTIONS

(Class method) Open a new folder. OPTIONS is a list of labeled parameters
defining options for the mailboxes. Some options pertain to C<Mail::Box>, and
others are added by sub-classes. The list below describes all the options
provided by C<Mail::Box> and the various sub-classes distributed with it. Those
provided by the C<Mail::Box> class are described in detail here. For a
description of the other options, see the documentation for the respective
sub-class.

 OPTION            DEFINED BY         DEFAULT
 access            Mail::Box          'r'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          undef
 head_wrap         Mail::Box          72
 extract           Mail::Box          10kb
 log               Mail::Reporter     'WARNINGS'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Box          <depends on folder location>

Only useful to write extension to C<Mail::Box>, for instance within the
implementation of C<Mail::Box::Mbox>.  Common users of folders
you will not specify these:

 OPTION            DEFINED BY         DEFAULT
 body_type         Mail::Box::Mbox    <see below, folder specific>
 body_delayed_type Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options    Mail::Box          []
 head_type         Mail::Box          'Mail::Message::Head::Complete'
 locker            Mail::Box          undef
 lock_type         Mail::Box          'Mail::Box::Locker::DotLock'
 lock_file         Mail::Box          foldername.'.lock'
 lock_timeout      Mail::Box          1 hour
 lock_wait         Mail::Box          10 seconds
 multipart_type    Mail::Box          'Mail::Message::Body::Multipart'
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::Message'
 organization      Mail::Box          'FILE'

The normal usage options for C<Mail::Box::new()> are:

=over 4

=item * access =E<gt> MODE

Access-rights to the folder. MODE can be read-only (C<"r">), append (C<"a">),
and read-write (C<"rw">).  Folders are opened for read-only (C<"r">) by
default.

These modes have nothing in common with the modes actually used to open the
folder-files within this module.  For instance, if you specify C<"rw">, and
open the folder, only read-permission on the folder-file is required.  Writing
to a folder will always create a new file to replace the old one.

=item * folder =E<gt> FOLDERNAME

Which folder to open (for reading or writing). When used for reading (the
C<access> option set to C<"r"> or C<"a">) the mailbox should already exist
and be readable. The file or directory of the mailbox need not exist if it
is opened for reading and writing (C<"rw">).  Write-permission is checked when
opening an existing mailbox.

=item * folderdir =E<gt> DIRECTORY

Where are folders written by default?  You can specify a folder-name
preceeded by C<=> to explicitly state that the folder is located below
this directory.  For example: if C<folderdir =E<gt> '/tmp'> and
C<folder =E<gt> '=abc'>, then the name of the folder-file is C<'/tmp/abc'>.

=item * head_wrap =E<gt> INTEGER

Fold the structured headers to the specified length (defaults to C<72>).
Folding is disabled when C<0> is specified.

=item * save_on_exit =E<gt> BOOL

Sets the policy for saving the folder when it is closed. (See the
C<close()> method.)  A folder can be closed manually or via a number of
implicit methods (including when the program is terminated). By default
this option is set to TRUE.

=item * remove_when_empty =E<gt> BOOLEAN

Determines whether or not to remove the folder file or directory
automatically when the write would result in a folder without sub-folders
or messages. This option is dependent on the type of folder, and is true by
default.

=item * trusted =E<gt> BOOLEAN

Flags whether to trust the data in the folder or not.  Folders which
reside in your C<folderdir> will be trusted by default, but folders
which are outside it will need some extra checking.

If you do not check encodings of received messages, you may print
text messages with binary data to the screen.  This is a security risk.

=back

To control delay-loading of messages, as well the headers as the bodies,
the next three option specify the algorithm. C<extract> determines whether
we want delay-loading, and C<body_type> determines which kind of body we want
when we decide to parse it.

=over 4

=item * extract =E<gt> INTEGER

=item * extract =E<gt> CODE

=item * extract =E<gt> METHOD

=item * extract =E<gt> 'LAZY'|'ALWAYS'

When the header of a message is read, you may want to postpone the
reading of the body.  Header information is more often needed than
the body data, so why parse it always together?  The cost of delaying
is not too high.

If you supply a number to this option, bodies of those messages with a
total size less than that number will be extracted from the folder only
when nessesary.

If you supply a code reference, that subroutine is called every time
that the extraction mechanism wants to determine whether to parse the
body or not. The subroutine is called with the following arguments:

    $code->(FOLDER, HEAD)

where FOLDER is a reference to the folder we are reading.  HEAD refers to a
C<Mail::Message::Head>.  The routine must return a true value (extract now)
or a false value (be lazy, do not parse yet).  Think about using the
C<guessBodySize()> and C<guessTimestamp()> on the header to determine
your choice.

The third possibility is to specify the NAME of a method.  In that case,
for each message is called:

   FOLDER->NAME(HEAD)

Where each parameter has the same meaning as described above.

The fourth way to use this parameter involves constants: with C<'LAZY'>
all messages will be delayed. With C<'ALWAYS'> you force unconditional
loading.

Examples:

    $folder->new(extract => 'LAZY');
    $folder->new(extract => 10000);
    $folder->new(extract => sub
       { my ($f, $head) = @_;
         my $size = $head->guessBodySize;
         defined $size ? $size < 10000 : 1
       }); #same

    $folder->new(extract => 'sent_by_me');
    sub Mail::Box::send_by_me($$)
    {   my ($self, $header) = @_;
        $header->get('from') =~ m/\bmy\@example.com\b/i;
    }

=item * body_type =E<gt> CLASS|CODE

When messages are read from a folder-file, the headers will be stored in
a C<head_type>-object.  For the body, however, there is a range of
choices about type, which are all described in the C<Mail::Message::Body>
manual page.

Specify a CODE-reference which produces the body-type to be created, or
a CLASS of the body which is used when the body is not a multipart.  In case
of a code, the header-structure is passed as first argument to the routine.

Do I<not> return a delayed body-type (like C<::Delayed>), because that is
determined by the C<extract()> method.  Do always check for multipart
messages, otherwise your parts (I<attachments>) will not be split-up.

For instance:

   $mgr->open(body_type => \&which_body);

   sub which_body($) {
       my $head = shift;
       my $size = $head->guessBodySize || 0;
       my $type = $size > 100000 ? 'File' : 'Lines';
       "Mail::Message::Body::$type";
   }

The default depends on the mail-folder type, although the general default
is C<Mail::Message::Body::Lines>.  Please check the applicatable
manual pages.

=back

Options for extension-writers are:

=over 4

=item * coerce_options =E<gt> ARRAY

Keep configuration information for messages which are coerced into the
specified folder type, starting with a different folder type (or even
no folder at all).

Messages which are coerced are always fully read, so this kind of information
does not need to be kept here.

=item * head_type =E<gt> CLASS

The type of header which contains all header information.  Must extend
C<Mail::Message::Head::Complete>.

=item * lock_type =E<gt> CLASS|STRING

The type of the locker object.  This may be the full name of a CLASS
which extends C<Mail::Box::Locker>, or one of the known locker types
C<'DotLock'>, C<'File'>, C<'NFS'>, or C<'NONE'>.

=item * locker =E<gt> OBJECT

An OBJECT which extends C<Mail::Box::Locker>, and will handle
folder locking replacing the default lock behavior.

=item * manager =E<gt> MANAGER

A reference to the object which manages this folder -- typically an
C<Mail::Box::Manager> instance.

=item * message_type =E<gt> CLASS

What kind of message-objects are stored in this type of folder.  The
default is Mail::Box::Message (which is a sub-class of Mail::Message).
The class you offer must be an extension of C<Mail::Box::Message>.

=item * organization =E<gt> 'FILE' | 'DIRECTORY'

Tells whether a folder is one file containing many messages (like
Mbox-folders) or one directory per folder, a message per file
(like MH-folders).

=back

=cut

sub new(@)
{   my $class        = shift;

    if($class eq __PACKAGE__)
    {   my $package = __PACKAGE__;

        croak <<USAGE;
You should not instantiate $package directly, but rather one of the
sub-classes, such as Mail::Box::Mbox.  If you need automatic folder
type detection then use Mail::Box::Manager.
USAGE
    }

    my $self = $class->SUPER::new
      ( @_
      , init_options => [ @_ ]  # for clone
      ) or return;

    $self->read if $self->{MB_access} =~ /r|a/;
    $self;
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $class      = ref $self;
    my $foldername = $args->{folder} || $ENV{MAIL};
    unless($foldername)
    {   $self->log(ERROR => "No folder specified: specify the folder option or set the MAIL environemt variable.");
        return;
    }

    $self->{MB_foldername}   = $foldername;
    $self->{MB_init_options} = $args->{init_options};
    $self->{MB_coerce_opts}  = $args->{coerce_options}    || [];
    $self->{MB_access}       = $args->{access}            || 'r';
    $self->{MB_remove_empty} = $args->{remove_when_empty} || 1;
    $self->{MB_messages}     = [];
    $self->{MB_save_on_exit} = $args->{save_on_exit}      || 1;
    $self->{MB_organization} = $args->{organization}      || 'FILE';
    $self->{MB_head_wrap}    = $args->{head_wrap} if defined $args->{head_wrap};

    my $folderdir = $self->folderdir($args->{folderdir});
    $self->{MB_trusted}      = exists $args->{trusted} ? $args->{trusted}
      : substr($foldername, 0, 1) eq '='               ? 1
      : substr($foldername, 0, length $folderdir) eq $folderdir;

    if(exists $args->{manager})
    {   $self->{MB_manager}      = $args->{manager};
        weaken($self->{MB_manager});
    }

    my $message_type = $self->{MB_message_type}
        = $args->{message_type}     || $class . '::Message';
    $self->{MB_body_type}
        = $args->{body_type}        || 'Mail::Message::Body::Lines';
    $self->{MB_body_delayed_type}
        = $args->{body_delayed_type}|| 'Mail::Message::Body::Delayed';
    $self->{MB_multipart_type}
        = $args->{multipart_type}   || 'Mail::Message::Body::Multipart';
    my $headtype     = $self->{MB_head_type}
        = $args->{MB_head_type}     || 'Mail::Message::Head::Complete';

    confess "head_type must be complete, but is $headtype.\n"
        unless $headtype->isa('Mail::Message::Head::Complete');

    my $extract  = $args->{extract} || 10000;
    $self->{MB_extract}
      = ref $extract eq 'CODE' ? $extract
      : $extract eq 'ALWAYS'   ? sub {1}
      : $extract eq 'LAZY'     ? sub {0}
      : $extract eq 'NEVER'    ? sub {1}  # compatibility
      : $extract =~ m/\D/      ? sub {no strict 'refs';shift->$extract(@_)}
      :                          $extract;  # digits stay to avoid closure.

    #
    # Create a locker.
    #

    my $locker;
    if($locker = $args->{locker}) {;}
    else
    {   $locker = Mail::Box::Locker->new
            ( folder   => $self
            , method   => $args->{lock_type}
            , timeout  => $args->{lock_timeout}
            , wait     => $args->{lock_wait}
            , file     => $args->{lockfile} || $args->{lock_file}
            );
    }
    $self->{MB_locker} = $locker;
    $self;
}

#-------------------------------------------

=item close OPTIONS

lose the folder, optionally writing it. C<close> takes the same options as
C<write>, as well as a few others:

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

=over 4

=item * write =E<gt> 'ALWAYS'|'NEVER'|'MODIFIED'

Specifies whether the folder should be written.  As could be expected,
C<'ALWAYS'> means always (even if there are no changes), C<'NEVER'> means that
changes to the folder will be lost, and C<'MODIFIED'> (which is the default)
only saves the folder if there are any changes.

=item * force =E<gt> BOOL

Override the C<access> setting specified when the folder was opened. This
option only has an effect if its value is TRUE. NOTE: Writing to the folder
may not be permitted by the operating system, in which case even C<force> will
not help.

=back

=cut

sub close(@)
{   my ($self, %args) = @_;
    my $force = $args{force} || 0;

    return if exists $self->{MB_is_closed};
    $self->{MB_is_closed} = 1;

    # Inform manager that the folder is closed.
    $self->{MB_manager}->close($self)
        if exists $self->{MB_manager}
           && !$args{close_by_manager};

    delete $self->{MB_manager};

    my $write
      = !exists $args{write} || $args{write} eq 'MODIFIED' ? $self->modified
        : $args{write} eq 'ALWAYS'                         ? 1
        : $args{write} eq 'NEVER'                          ? 0
        :                                                    0;

    if($write && !$force && !$self->writeable)
    {   $self->log(WARNING => "Changes not written to read-only folder");
        return 1;
    }

    my $rc = $write ? $self->write(force => $force) : 1;

    $self->{MB_locker}->unlock;
    $rc;
}

#-------------------------------------------

=item locker

Returns the locking object.

=cut

sub locker() { shift->{MB_locker}}

#-------------------------------------------

=item delete

Remove the specified folder file or folder directory (depending on
the type of folder) from disk.  Of course, THIS IS DANGEROUS: you "may"
lose data.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before deleting the source folder.  Otherwise you may lose
data if the system crashes or if there are software problems.

Examples:

   my $folder = Mail::Box::File->new(folder => 'InBox');
   $folder->delete;

=cut

sub delete()
{   my $self = shift;

    # Extra protection: do not remove read-only folders.
    unless($self->writeable)
    {   warn "Folder $self is opened read-only, so not removed.\n";
        return;
    }

    # Sub-directories need to be removed first.
    foreach ($self->listSubFolders)
    {   my $sub = $self->openSubFolder($_);
        next unless $sub;
        $sub->delete;
        $sub->close;
    }

    # A lock may protect destruction from interference.
    my $locker = $self->locker;
    $locker->lock if $locker;
    $_->delete foreach $self->messages;
    $self->{MB_remove_empty} = 1;

    my $rc = $self->write(keep_deleted => 0);
    $locker->unlock if $locker;

    $rc;
}

#-------------------------------------------

=item openSubFolder NAME [,OPTIONS]

Open (or create, if it does not exist yet) a new subfolder in an
existing folder.

Example:

    my $folder = Mail::Box::Mbox->new(folder => '=Inbox');
    my $sub    = $folder->openSubFolder('read');

=cut

sub openSubFolder(@)
{   my $self    = shift;
    my @options = (@{$self->{MB_init_options}}, @_);

    $self->{MB_manager}
    ?  $self->{MB_manager}->open(@options)
    :  (ref $self)->new(@options);
}

#-------------------------------------------

=item name

Returns the name of the folder.  What the name represents depends on
the actual type of mailbox used.

Example:

   print $folder->name;

=cut

sub name() {shift->{MB_foldername}}

#-------------------------------------------

=item writeable

Checks whether the current folder is writeable.

Example:

    $folder->addMessage($msg) if $folder->writeable;

=cut

sub writeable() {shift->{MB_access} =~ /w|a/ }
sub readable()  {1}  # compatibility

#-------------------------------------------

=item modified [BOOLEAN]

C<modified> checks if the folder is modified, optionally after setting the
flag.   A folder is modified when any of the messages is to be deleted, any
of the messages has changed, or messages are added after the folder was
read from file.

=cut

sub modified($)
{   my $self     = shift;
    return $self->{MB_modified} = shift if @_;
    return 1 if $self->{MB_modified};

    foreach (@{$self->{MB_messages}})
    {   next unless $_->deleted || $_->modified;
        return $self->{MB_modified} = 1;
    }

    0;
}

#-------------------------------------------

=item message INDEX [,MESSAGE]

Get or set a message with on a certain index.  Messages which are flagged
for deletion are counted.  Negative indexes start at the end of the folder.

See the C<activeMessage> method to index message that are not marked
for deletion.

Examples:

    my $msg = $folder->message(3);
    $folder->message(3)->delete;   # status changes to `deleted'
    $folder->message(3, $msg);
    print $folder->message(-1);    # last message.

=cut

sub message(;$$)
{   my ($self, $index) = (shift, shift);
    @_ ?  $self->{MB_messages}[$index] = shift : $self->{MB_messages}[$index];
}

#-------------------------------------------

=item messageId MESSAGE-ID [,MESSAGE]

With one argument, returns the message in the folder with the specified
MESSAGE-ID. If a reference to a message object is passed as the optional
second argument, the message is first stored in the folder, replacing any
existing message whose message ID is MESSAGE-ID. (The message ID of MESSAGE
need not match MESSAGE-ID.)

The MESSAGE-ID may still be in angles, which will be stripped.  In that
case blanks (which origin from header line folding) are removed too.  Other
info around the angles will be removed too.

WARNING: when the message headers are delay-parsed, the message might be in
the folder but not yet parsed into memory. In this case, use the C<find()>
method instead of C<messageId> if you really need a thorough search.

Examples:

   my $msg = $folder->messageId('<complex-message.id>');
   $folder->messageId("<complex-message\n.id>", $msg);
   my $msg = $folder->messageId('complex-message.id');
   my $msg = $folder->messageId('garbage <complex-message.id> trash');

=cut

sub messageId($;$)
{   my ($self, $msgid) = (shift, shift);

    if($msgid =~ m/\<([^>]+)\>/s )
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }

    return $self->{MB_msgid}{$msgid} unless @_;
    my $message = shift;

    # Undefine message?
    unless($message)
    {   delete $self->{MB_msgid}{$msgid};
        return;
    }

    # Auto-delete doubles.
    if(my $double = $self->{MB_msgid}{$msgid})
    {   $message->delete unless $double->isa('Mail::Box::Message::Dummy');
        return $message;
    }

    $self->{MB_msgid}{$msgid} = $message;
}

sub messageID(@) {shift->messageId(@_)} # compatibility

#-------------------------------------------

=item find MESSAGE-ID

Like C<messageId()>, this method searches for a message with the
MESSAGE-ID, returning the corresponding message object.  However, C<find()>
will cause unparsed message in the folder to be parsed until the message-id
is found.  The folder will be scanned back to front.

=cut

sub find
{   my ($self, $msgid) = (shift, shift);
    my $msgids = $self->{MB_msgid};

    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }

    return $msgids->{$msgid} if exists $msgids->{$msgid};
    $self->scanForMessages(undef, $msgid, 'EVER', 'ALL');
    $msgids->{$msgid};
}

#-------------------------------------------

=item messages

Returns all messages.  In scalar context, it returns the number of undeleted
messages in the folder.  Dereferencing a folder to an array is overloaded
to call this method.

Examples:

    foreach my $message ($folder->messages) {...}
    foreach my $message (@$folder) {...}
    my @messages   = $folder->messages;
    my @not_deleted= grep {! $_->deleted} $folder->messages;
    my $nr_of_msgs = $folder->messages;
    $folder->[2];   # third message

=cut

sub messages() { @{shift->{MB_messages}} }

#-------------------------------------------

=item allMessageIds

Returns a list of I<all> message-ids in the folder, including
those of messages which are to be deleted.

For some folder-types (like MH), this method may cause all message-files
to be read.  See their respective manual pages.

Examples:

    foreach my $id ($folder->allMessageIds) {
        $folder->messageId($id)->print;
    }

=cut

sub allMessageIds() { keys %{shift->{MB_msgid}} }
sub allMessageIDs() {shift->allMessageIds}  # compatibilty

#-------------------------------------------

=item addMessage  MESSAGE

=item addMessages MESSAGE [, MESSAGE, ...]

Add a message to the folder.  A message is usually a C<Mail::Box::Message>
object or a sub-class thereof.  The message shall not be in an other folder,
when you use this method.  In case it is, use C<moveMessage()> or
C<copyMessage()>.

Messages with id's which already exist in this folder are not added.

Examples:

   $folder->addMessage($msg);
   $folder->addMessages($msg1, $msg2, ...);

=cut

sub addMessage($)
{   my $self    = shift;
    my $message = shift or return $self;

    confess <<ERROR if $message->can('folder') && $message->folder;
You cannot add a message which is already part of a folder to a new
one.  Please use moveMessage or copyMessage.
ERROR

    # Force the message into the right folder-type.
    my $coerced = $self->coerce($message);
    $coerced->folder($self);

    unless($message->head->isDelayed)
    {   # Do not add the same message twice.
        my $msgid = $message->messageId;
        if(my $found = $self->messageId($msgid))
        {   $message->delete;
            return $found;
        }

        $self->messageId($msgid, $message);
        $self->toBeThreaded($message);
    }

    $self->storeMessage($coerced);
    $self->{MB_modified}++;
    $coerced;
}

sub addMessages(@)
{   my $self = shift;
    $self->addMessage($_) foreach @_;
    $self;
}

#-------------------------------------------

=item current [NUMBER|MESSAGE|MESSAGE-ID]

Some mail-readers keep the I<current> message, which represents the last
used message.  This method returns [after setting] the current message.
You may specify a NUMBER, to specify that that message number is to be
selected as current, or a MESSAGE/MESSAGE-ID (as long as you are sure that the
header is already loaded, otherwise they are not recognized).

Examples:

   $folder->current(0);
   $folder->current($message);

=cut

sub current(;$)
{   my $self = shift;
    return $self->{MB_current} || $self->message(-1)
        unless @_;

    my $next = shift;
    if(my $previous = $self->{MB_current})
    {    $previous->setLabel(current => 0);
    }

    ($self->{MB_current} = $next)->setLabel(current => 1);
}


#-------------------------------------------

=item create FOLDERNAME [, OPTIONS]

(Class method) Create a folder.  If the folder already exists, it will
be left unchanged.  As options, you may specify:

=over 4

=item * folderdir =E<gt> DIRECTORY

When the foldername is preceeded by a C<=>, the C<folderdir> directory
will be searched for the named folder.

=back

=cut

sub create($@)
{   my ($class, $name, @options) = @_;
    die "$class cannot create a folder named $name.\n";
}

#-------------------------------------------

=item listSubFolders OPTIONS

(Class and Instance method)
List the names of all sub-folders to this folder.  Use these names
in C<openSubFolder>, to open these folders on a mailbox type way.
For Mbox-folders, sub-folders are simutated.

 OPTION            DEFINED BY         DEFAULT
 folder            Mail::Box          <obligatory>
 folderdir         Mail::Box          <from object>
 check             Mail::Box          <false>
 skip_empty        Mail::Box          <false>

The options general to all folder types are:

=over 4

=item * folder =E<gt> FOLDERNAME

The folder whose sub-folders should be listed.

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

Specifies whether empty folders (folders which currently do not contain any
messages) should be included. It may not be useful to open empty folders, but 
saving to them is useful.

=item * skip_empty =E<gt> BOOL

Shall empty folders (folders which currently do not contain any messages)
be included?  Empty folders are not useful to open, but may be useful
to save to.

=back

Examples:

   my $folder = $mgr->open('=in/new');
   my @subs = $folder->listSubFolders;

   my @subs = Mail::Box::Mbox->listSubFolders(folder => '=in/new');
   my @subs = Mail::Box::Mbox->listSubFolders; # toplevel folders.

=cut

sub listSubFolders(@)
{   my ($class, @options) = @_;
    confess "Folder or class $class cannot list folders.\n";
}

#-------------------------------------------

=back

=head1 METHODS for extensions writers

The next set of methods is for normal use, but only for people who
write entensions (develop new folder types).

=over 4

=cut

#-------------------------------------------

=item clone OPTIONS

Create a new folder, with the same settings as this folder.  One of
the specified options must be new folder to be opened.  Other options
overrule those of the folder where this is a clone from.

Example:

   my $folder2 = $folder->clone(folder => '=jan');

=cut

sub clone(@)
{   my $self  = shift;

    (ref $self)->new
     ( @{$self->{MB_init_options}}
     , @_
     );
}

#-------------------------------------------

=item read OPTIONS

Read messages from the folder into memory.  The OPTIONS are folder
specific.

NOTE: if you are copying messages from one folder to another, use
C<addMessages> instead of C<read>.

=cut

sub read(@)
{   my $self = shift;
    $self->{MB_open_time}    = time;

    local $self->{MB_lazy_permitted} = 1;

    # Read from existing folder.
    return unless $self->readMessages
      ( trusted      => $self->{MB_trusted}
      , head_wrap    => $self->{MB_head_wrap}
      , head_type    => $self->{MB_head_type}
      , message_type => $self->{MB_message_type}
      , body_delayed_type => $self->{MB_body_delayed_type}
      , @_
      );

    if($self->{MB_modified})
    {   $self->log(INTERNAL => "Modified $self->{MB_modified}");
        $self->{MB_modified} = 0;  #after reading, no changes found yet.
    }

    $self;
}

#-------------------------------------------

=item determineBodyType MESSAGE, HEAD

Determine which kind of body will be created for this message when
reading the folder initially.

=cut

sub determineBodyType($$)
{   my ($self, $message, $head) = @_;

    if($self->{MB_lazy_permitted} && !$message->isPart)
    {   my $delayed = $self->{MB_body_delayed_type};
        my $extract = $self->{MB_extract};

        return $delayed
             if ref $extract && !$extract->($self, $head);

        my $size = $head->guessBodySize;
        return $delayed if $size && $size > $extract;
    }

    return $self->{MB_multipart_type}
        if $head->isMultipart;

    my $bodytype = $self->{MB_body_type};
    ref $bodytype ? $bodytype->($head) : $bodytype;
}

sub extractDefault($)
{   my ($self, $head) = @_;
    my $size = $head->guessBodySize;
    defined $size ? $size < 10000 : 0  # immediately extract < 10kb
}

sub lazyPermitted($)
{   my $self = shift;
    $self->{MB_lazy_permitted} = shift;
}

#-------------------------------------------

=item storeMessage MESSAGE

Store the message in the folder without the checks as performed by
C<addMessage>.

=cut

sub storeMessage($)
{   my ($self, $message) = @_;

    push @{$self->{MB_messages}}, $message;
    $message->seqnr( @{$self->{MB_messages}} -1);
    $message;
}

#-------------------------------------------

=item write OPTIONS

Write the data to disk.  The folder is returned if successful. To write to a
different file, you must first create a new folder, then move the messages,
and then write the folder.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

 OPTION            DEFINED BY         DEFAULT
 force             Mail::Box          <true>
 head_wrap         Mail::Box          72
 keep_deleted      Mail::Box          <false>
 save_deleted      Mail::Box          <false>

=over 4

=item * force =E<gt> BOOL

Override write-protection by the C<access> option while opening the folder
(whenever possible, it may still be blocked by the operating system).

=item * keep_deleted =E<gt> BOOL

Do not remove messages which were flagged to be deleted from the folder
from memory, but do remove them from disk.

=item * save_deleted =E<gt> BOOL

Do also write messages which where flagged to be deleted to their folder.  The
flag is conserved (when possible), which means that the next write may
remove them for real.

=back

=cut

sub write(@)
{   my ($self, %args) = @_;

    unless($args{force} || $self->writeable)
    {   warn "Folder $self is opened read-only.\n";
        return;
    }

    $args{save_deleted} = 1 if $args{keep_deleted};

    my @messages = $self->messages;
    my @keep;

    foreach my $message (@messages)
    {
        unless($message->deleted)
        {   push @keep, $message;
            next;
        }

        $message->diskDelete
            unless $args{save_deleted};

        if($args{keep_deleted}) {push @keep, $message}
        else
        {   $message->head(undef);
            $message->body(undef);
        }
    }

    $self->{MB_messages} = \@keep unless @keep==@messages;

    if(@keep!=@messages || $self->modified)
    {   $args{messages} = \@keep;
        $self->writeMessages(\%args);
        $self->modified(0);
    }
    else
    {   $self->log(PROGRESS => "Folder $self not changed, so not updated.");
    }

    $self;
}

#-------------------------------------------

=item coerce MESSAGE

Coerce the MESSAGE to be of the correct type to be placed in the
folder.  You are not may specify C<Mail::Internet> and C<MIME::Entity>
here: they will be translated into C<Mail::Message> messages first.

=cut

sub coerce($)
{   my ($self, $message) = @_;
    $self->{MB_message_type}->coerce($message);
}

#-------------------------------------------

=item organization

Return whether a folder is organized as one 'FILE' with many messages or
a 'DIRECTORY' with one message per file.

=cut

sub organization() { shift->{MB_organization} }

#-------------------------------------------

=item folderdir [DIR]

Get or set the directory which is used to store mail-folders by default.

Examples:

   print $folder->folderdir;
   $folder->folderdir("$ENV{HOME}/nsmail");

=cut

sub folderdir(;$)
{   my $self = shift;
    if(@_)
    {   my $newdir = shift;
        $newdir   .= ($^O =~ m/^Win/i ? '\\' : '/')
            unless $newdir =~ m![/\\]$!;

        $self->{MB_folderdir} = $newdir;
    }
    $self->{MB_folderdir};
}

#-------------------------------------------

=item readMessages

Called by C<read()> to actually read the messages from one specific
folder type.  The C<read()> organizes the general activities.

=cut

sub readMessages(@) {shift->notImplemented}

#-------------------------------------------

=item writeMessages

Called by C<write()> to actually write the messages from one specific
folder type.  The C<write()> organizes the general activities.

=cut

sub writeMessages(@) {shift->notImplemented}

#-------------------------------------------

=item appendMessages OPTIONS

(Class method) Append one or more messages to an unopened folder.
Usually, this method is called by the Mail::Box::Manager (its method
C<appendMessage()>), in which case the correctness of the
folder type is checked.
 
This method takes a list of labeled parameters, which may contain
any option which can be used when a folder is opened (most importantly
C<folderdir>).  Two aditional parameters shall be specified:

=over 4

=item * folder =E<gt> FOLDERNAME

The name of the folder to which the messages are to be appended.  The folder
implementation will avoid opening the folder when possible, because this is
resource consuming.

=item * message =E<gt> MESSAGE

=item * messages =E<gt> ARRAY-OF-MESSAGES

One reference to a MESSAGE or a reference to an ARRAY of MESSAGEs, which may
be of any type.  The messages will be first coerced into the correct
message type to fit in the folder, and then will be added to it.

=back

Examples:

    my $message = Mail::Message->new(...);
    Mail::Box::Mbox->appendMessages
      ( folder    => '=xyz'
      , message   => $message
      , folderdir => $ENV{FOLDERS}
      );

better:

    my Mail::Box::Manager $mgr;
    $mgr->appendMessages($message, folder => '=xyz');

=cut

sub appendMessages(@) {shift->notImplemented}

#-------------------------------------------

=item foundIn [FOLDERNAME], OPTIONS

(class method) Determine if the specified folder is of the type handled by the
folder class. This method is extended by each folder sub-type.

The FOLDERNAME specifies the name of the folder, as is specified by the
application.  You need to specified the C<folder> option when you skip
this first argument.

OPTIONS is a list of extra information for the request.  Read
the documentation for each type of folder for folder-specific options, but
each folder class will at least support the C<folderdir> option:

=over 4

=item * folderdir =E<gt> DIRECTORY

The location where the folders of this class are stored by default.  If the
user specifies a name starting with a C<=>, that indicates that the folder is
to be found in this default DIRECTORY.

=back

Examples:

   Mail::Box::Mbox->foundIn('=markov', folderdir => "$ENV{HOME}/Mail");
   Mail::Box::MH->foundIn(folder => '=markov');

=cut

sub foundIn($@)
{   my ($class, $folder, @options) = @_;
    $class->notImplemented;
}

#-------------------------------------------

=item toBeThreaded MESSAGES

=item toBeUnthreaded MESSAGES

The specified message is ready to be included in (or remove from) a thread.
This will be passed on to the mail-manager, which keeps an overview on
which thread-detection objects are floating around.

=cut

sub toBeThreaded(@)
{   my $self = shift;

    my $manager = $self->{MB_manager}
       or return $self;

    $manager->toBeThreaded($self, @_);
    $self;
}

sub toBeUnthreaded(@)
{   my $self = shift;

    my $manager = $self->{MB_manager}
       or return $self;

    $manager->toBeThreaded($self, @_);
    $self;
}

#-------------------------------------------

=item scanForMessages MESSAGE, MESSAGE-IDS, TIMESTAMP, WINDOW

The MESSAGE which is known contains references to messages before
it which are not found yet.  But those messages can be in the same
folder.  Scan back in this folder for the MESSAGE-IDS (which may be
one string or a reference to an array of strings).  The TIMESTAMP
and WINDOW (see options in new()) limit the search.

=cut

sub scanForMessages($$$$)
{   my ($self, $startid, $msgids, $moment, $window) = @_;
    return $self unless $self->messages;  # empty folder.

    # Set-up window-bound.
    my $bound;
    if($window eq 'ALL')
    {   $bound = 0;
    }
    elsif(defined $startid)
    {   my $startmsg = $self->messageId($startid);
        $bound = $startmsg->nr - $window if $startmsg;
        $bound = 0 if $bound < 0;
    }

    my $last = ($self->{MBM_last} || $self->messages) -1;
    return $self if $bound >= $last;

    # Set-up time-bound
    my $after = $moment eq 'EVER' ? 0 : $moment;

    # Set-up msgid-list
    my %search = map {($_, 1)} ref $msgids ? @$msgids : $msgids;

    while(!defined $bound || $last >= $bound)
    {   my $message = $self->message($last);
        my $msgid   = $message->messageId;  # triggers load of head

        if(delete $search{$msgid})
        {   last unless keys %search;
        }

        last if $message->timestamp < $after;
        $last--;
    }

    $self->{MBM_last} = $last;
    keys %search;
}

#-------------------------------------------

=item sort PREPARE, COMPARE, LIST

(class method) Implements a general sort, with preparation phase.
First prepare a value foreach each element of the list by calling
the specified routine with the element as first argument.  Then
sort it based on the COMPARE routine.  In this case, the two argumements
to be compared are parsed.

=cut

sub sort(@)
{   my ($class, $prepare, $compare) = splice @_, 0, 3;
    return () unless @_;

    my %value = map { ($prepare->($_) => $_) } @_;
    map { $value{$_} } sort {$compare->($a, $b)} keys %value;
}

#-------------------------------------------

=item timespan2seconds TIME

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:

    '1 hour'
    '4 weeks'

=cut

sub timespan2seconds($)
{
    if( $_[1] =~ /^\s*(\d+\.?\d*|\.\d+)\s*(hour|day|week)s?\s*$/ )
    {     $2 eq 'hour' ? $1 * 3600
        : $2 eq 'day'  ? $1 * 86400
        :                $1 * 604800;  # week
    }
    else
    {   carp "Invalid timespan '$_' specified.\n";
        undef;
    }
}


#-------------------------------------------

=item DESTROY

This method is called by Perl when an folder-object is no longer accessible
by the rest of the program.

=cut

sub DESTROY
{   my $self = shift;
    $self->close unless $self->inGlobalDestruction || $self->{MB_is_closed};
}

#-------------------------------------------
# Instance variables
# MB_access: new(access)
# MB_body_type: new(body_type)
# MB_coerce_opts: Options which have to be applied to the messages which
#    are coerced into this folder.
# MB_current: Used by some mailbox-types to save last read message.
# MB_folderdir: new(folderdir)
# MB_foldername: new(folder)
# MB_head_type: new(head_type)
# MB_init_options: A copy of all the arguments given to the constructor
# MB_is_closed: Whether or not the mailbox is closed
# MB_extract: When to extract the body on the moment the header is read
# MB_locker: A reference to the mail box locker.
# MB_manager: new(manager)
# MB_messages: A list of all the messages in the folder
# MB_message_type: new(message_type)
# MB_modified: true when the message is modified for sure
# MB_msgid: A hash of all the messages in the mailbox, keyed on message ID
# MB_open_time: The time at which a mail box is first opened
# MB_organization: new(organization)
# MB_remove_empty: new(remove_when_empty)
# MB_save_on_exit: new(save_on_exit)

#-------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;