
use strict;
use warnings;

package Mail::Box;
use base 'Mail::Reporter';

use Mail::Box::Message;
use Mail::Box::Locker;
use File::Spec;

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

Mail::Box - manage a message-folder.

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open(folder => $ENV{MAIL}, ...);
 print $folder->name;

 # Get the first message.
 print $folder->message(0);

 # Delete the third message
 $folder->message(3)->delete;

 # Get the number of messages in scalar context.
 my $emails = $folder->messages;

 # Iterate over the messages.
 foreach ($folder->messages) {...}     # all messages
 foreach (@$folder) {...}              # all messages

 $folder->addMessage(new Mail::Box::Message(...));

Tied-interface:   (See Mail::Box::Tie)

 tie my(@inbox), 'Mail::Box::Tie::ARRAY', $inbox;
 $inbox[3]->print        # same as $folder->message(3)->print

 tie my(%inbox), 'Mail::Box::Tie::HASH', $inbox;
 $inbox{$msgid}->print   # same as $folder->messageId($msgid)->print

=head1 DESCRIPTION

A Mail::Box::Manager creates Mail::Box objects.  But you already
knew, because you started with the Mail::Box-Overview manual page.
That page is obligatory reading, sorry!

Mail::Box is the base class for accessing various types of mail folder
organizational structures in a uniform way.  The various folder types vary
on how they store their messages. For example, a folder may store many
messages in a single file, or store each message in a separate file in a
directory. Similarly, there may be different techniques for locking the
folders.

No object will be of type Mail::Box: it is only used as base class
for the real folder types.  Mail::Box is extended by

=over 4

=item * Mail::Box::Mbox

A folder type in which all related messages are stored in one file.  This
is very common folder type for UNIX.

=item * Mail::Box::MH

This folder creates a directory for each folder, and a message is one
file inside that directory.  The message files are numbered.

=item * Mail::Box::Maildir

This folder creates a directory for each folder.  A folder directory
contains a C<tmp>, C<new>, and C<cur> subdirectory.  New messages are
first stored in C<new>, and later moved to C<cur>.  Each message is one
file with a name starting with timestamp.

=back

The Mail::Box is used to get Mail::Box::Message objects from the
mailbox.  Applications then usually use information or add information to the
message object. For instance, the application can set a label which indicates
whether a message has been replied to or not.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

(Class method) Open a new folder. OPTIONS is a list of labeled parameters
defining options for the mailboxes. Some options pertain to Mail::Box, and
others are added by sub-classes. The list below describes all the options
provided by Mail::Box and the various sub-classes distributed with it. Those
provided by the Mail::Box class are described in detail here. For a
description of the other options, see the documentation for the respective
sub-class.

To control delay-loading of messages, as well the headers as the bodies,
a set of C<*_type> options are available. C<extract> determines whether
we want delay-loading.

=option  access MODE
=default access 'r'

Access-rights to the folder. MODE can be read-only (C<"r">), append (C<"a">),
and read-write (C<"rw">).  Folders are opened for read-only (C<"r">) by
default.

These modes have nothing in common with the modes actually used to open the
folder-files within this module.  For instance, if you specify C<"rw">, and
open the folder, only read-permission on the folder-file is required.  Writing
to a folder will always create a new file to replace the old one.

=option  create BOOLEAN
=default create <false>

Automatically create the folder when it does not exist yet.  This will only
work when access is granted for writing or appending to the folder.  Be
careful: you may create a different folder type than you expect unless you
ensure the C<type> (See Mail::Box::Manager::open()).

=option  folder FOLDERNAME
=default folder $ENV{MAIL}

Which folder to open (for reading or writing). When used for reading (the
C<access> option set to C<"r"> or C<"a">) the mailbox should already exist
and be readable. The file or directory of the mailbox need not exist if it
is opened for reading and writing (C<"rw">).  Write-permission is checked when
opening an existing mailbox.

=option  folderdir DIRECTORY
=default folderdir undef

Where are folders written by default?  You can specify a folder-name
preceded by C<=> to explicitly state that the folder is located below
this directory.  For example: if C<folderdir =E<gt> '/tmp'> and
C<folder =E<gt> '=abc'>, then the name of the folder-file is C<'/tmp/abc'>.

=option  head_wrap INTEGER
=default head_wrap 72

Fold the structured headers to the specified length.
Folding is disabled when C<0> is specified.

=option  keep_dups BOOLEAN
=default keep_dups <false>

Indicates whether or not duplicate messages within the folder should          
be retained.  A message is considered to be a duplicate if its message-id      
is the same as a previously parsed message within the folder. If this         
option is false (the default) such messages are automatically deleted,
because it is useless to store the same message twice.

=option  save_on_exit BOOLEAN
=default save_on_exit <true>

Sets the policy for saving the folder when it is closed. (See close())
A folder can be closed manually or via a number of
implicit methods (including when the program is terminated).

=option  remove_when_empty BOOLEAN
=default remove_when_empty <true>

Determines whether or not to remove the folder file or directory
automatically when the write would result in a folder without sub-folders
or messages. This option is dependent on the type of folder.

=option  trusted BOOLEAN
=default trusted <depends on folder location>

Flags whether to trust the data in the folder or not.  Folders which
reside in your C<folderdir> will be trusted by default, but folders
which are outside it will need some extra checking.

If you do not check encodings of received messages, you may print
text messages with binary data to the screen.  This is a security risk.

=option  extract INTEGER | CODE | METHOD | 'LAZY'|'ALWAYS'
=default extract 10240

When the header of a message is read, you may want to postpone the
reading of the body.  Header information is more often needed than
the body data, so why parse it always together?  The cost of delaying
is not too high.

If you supply a number to this option, bodies of those messages with a
total size less than that number will be extracted from the folder only
when necessary.

If you supply a code reference, that subroutine is called every time
that the extraction mechanism wants to determine whether to parse the
body or not. The subroutine is called with the following arguments:

 $code->(FOLDER, HEAD)

where FOLDER is a reference to the folder we are reading.  HEAD refers to a
Mail::Message::Head.  The routine must return a true value (extract now)
or a false value (be lazy, do not parse yet).  Think about using the
guessBodySize() and guessTimestamp() on the header to determine
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

=option  body_type CLASS|CODE
=default body_type <folder specific>

When messages are read from a folder-file, the headers will be stored in
a C<head_type>-object.  For the body, however, there is a range of
choices about type, which are all described in the Mail::Message::Body
manual page.

Specify a CODE-reference which produces the body-type to be created, or
a CLASS of the body which is used when the body is not a multipart.  In case
of a code, the header-structure is passed as first argument to the routine.

Do I<not> return a delayed body-type (like C<::Delayed>), because that is
determined by the C<extract()> method.  Do always check for multipart
messages, otherwise your parts (I<attachments>) will not be split-up.

For instance:

 $mgr->open('InBox', body_type => \&which_body);

 sub which_body($) {
     my $head = shift;
     my $size = $head->guessBodySize || 0;
     my $type = $size > 100000 ? 'File' : 'Lines';
     "Mail::Message::Body::$type";
 }

The default depends on the mail-folder type, although the general default
is Mail::Message::Body::Lines.  Please check the applicable
manual pages.

=option  multipart_type CLASS
=default multipart_type 'Mail::Message::Body::Multipart'

The default type of objects which are to be created for multipart message
bodies.

=option  body_delayed_type CLASS
=default body_delayed_type 'Mail::Message::Body::Delayed'

The bodies which are delayed: which will be read from file when it
is needed, but not before.

=option  coerce_options ARRAY
=default coerce_options []

Keep configuration information for messages which are coerced into the
specified folder type, starting with a different folder type (or even
no folder at all).
Messages which are coerced are always fully read, so this kind of information
does not need to be kept here.

=option  field_type CLASS
=default field_type undef

The type of the fields to be used in a header. Must extend
Mail::Message::Field.

=option  head_type CLASS
=default head_type 'Mail::Message::Head::Complete'

The type of header which contains all header information.  Must extend
Mail::Message::Head::Complete.

=option  head_delayed_type CLASS
=default head_delayed_type 'Mail::Message::Head::Delayed'

The headers which are delayed: which will be read from file when it
is needed, but not before.

=option  lock_type CLASS|STRING
=default lock_type 'Mail::Box::Locker::DotLock'

The type of the locker object.  This may be the full name of a CLASS
which extends Mail::Box::Locker, or one of the known locker types
C<'DotLock'>, C<'File'>, C<'MULTI'>, C<'NFS'>, C<'POSIX'>, or C<'NONE'>.

=option  locker OBJECT
=default locker undef

An OBJECT which extends Mail::Box::Locker, and will handle
folder locking replacing the default lock behavior.

=option  lock_file FILENAME
=default lock_file undef

The name of the file which is used to lock.  This must be specified when
locking is to be used.

=option  lock_timeout SECONDS
=default lock_timeout 1 hour

When the lock file is older than the specified number of SECONDS, it is
considered a mistake.  The original lock is released, and accepted for
this folder.

=option  lock_wait SECONDS
=default lock_wait 10 seconds

SECONDS to wait before failing on opening this folder.

=option  manager MANAGER
=default manager undef

A reference to the object which manages this folder -- typically an
Mail::Box::Manager instance.

=option  message_type CLASS
=default message_type 'Mail::Box::Message'

What kind of message-objects are stored in this type of folder.  The
default is Mail::Box::Message (which is a sub-class of Mail::Message).
The class you offer must be an extension of Mail::Box::Message.

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

    $self->read if $self->{MB_access} =~ /r/;
    $self;
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $class      = ref $self;
    my $foldername = $args->{folder} || $ENV{MAIL};
    unless($foldername)
    {   $self->log(ERROR => "No folder specified: specify the folder option or set the MAIL environment variable.");
        return;
    }

    $self->{MB_foldername}   = $foldername;
    $self->{MB_init_options} = $args->{init_options};
    $self->{MB_coerce_opts}  = $args->{coerce_options}    || [];
    $self->{MB_access}       = $args->{access}            || 'r';
    $self->{MB_remove_empty}
         = defined $args->{remove_when_empty} ? $args->{remove_when_empty} : 1;

    $self->{MB_save_on_exit}
         = defined $args->{save_on_exit} ? $args->{save_on_exit} : 1;

    $self->{MB_messages}     = [];
    $self->{MB_organization} = $args->{organization}      || 'FILE';
    $self->{MB_head_wrap}    = $args->{head_wrap} if defined $args->{head_wrap};
    $self->{MB_linesep}      = "\n";
    $self->{MB_keep_dups}    = !$self->writable || $args->{keep_dups};

    my $folderdir = $self->folderdir($args->{folderdir});
    $self->{MB_trusted}      = exists $args->{trusted} ? $args->{trusted}
      : substr($foldername, 0, 1) eq '='               ? 1
      : substr($foldername, 0, length $folderdir) eq $folderdir;

    if(exists $args->{manager})
    {   $self->{MB_manager}  = $args->{manager};
        weaken($self->{MB_manager});
    }

    my $message_type = $self->{MB_message_type}
        = $args->{message_type}     || $class . '::Message';
    $self->{MB_body_type}
        = $args->{body_type}        || 'Mail::Message::Body::Lines';
    $self->{MB_body_delayed_type}
        = $args->{body_delayed_type}|| 'Mail::Message::Body::Delayed';
    $self->{MB_head_delayed_type}
        = $args->{head_delayed_type}|| 'Mail::Message::Head::Delayed';
    $self->{MB_multipart_type}
        = $args->{multipart_type}   || 'Mail::Message::Body::Multipart';
    my $headtype     = $self->{MB_head_type}
        = $args->{MB_head_type}     || 'Mail::Message::Head::Complete';
    $self->{MB_field_type}          = $args->{field_type};

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

=head2 Opening folders

=cut

#-------------------------------------------

=method clone OPTIONS

Create a new folder, with the same settings as this folder.  One of
the specified options must be new folder to be opened.  Other options
overrule those of the folder where this is a clone from.

=examples

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

=method create FOLDERNAME, OPTIONS

(Class method) Create a folder.  If the folder already exists, it will
be left unchanged.  As options, you may specify:

=option  folderdir DIRECTORY
=default folderdir undef

When the foldername is preceded by a C<=>, the C<folderdir> directory
will be searched for the named folder.

=cut

sub create($@) {shift->notImplemented}

#-------------------------------------------

=method folderdir [DIRECTORY]

Get or set the DIRECTORY which is used to store mail-folders by default.

=examples

 print $folder->folderdir;
 $folder->folderdir("$ENV{HOME}/nsmail");

=cut

sub folderdir(;$)
{   my $self = shift;
    $self->{MB_folderdir} = shift if @_;
    $self->{MB_folderdir};
}

#-------------------------------------------

=method foundIn [FOLDERNAME], OPTIONS

(class method) Determine if the specified folder is of the type handled by the
folder class. This method is extended by each folder sub-type.

The FOLDERNAME specifies the name of the folder, as is specified by the
application.  You need to specified the C<folder> option when you skip
this first argument.

OPTIONS is a list of extra information for the request.  Read
the documentation for each type of folder for folder-specific options, but
each folder class will at least support the C<folderdir> option:

=option  folderdir DIRECTORY
=default folderdir undef

The location where the folders of this class are stored by default.  If the
user specifies a name starting with a C<=>, that indicates that the folder is
to be found in this default DIRECTORY.

=examples

 Mail::Box::Mbox->foundIn('=markov', folderdir => "$ENV{HOME}/Mail");
 Mail::Box::MH->foundIn(folder => '=markov');

=cut

sub foundIn($@) { shift->notImplemented }

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

=method name

Returns the name of the folder.  What the name represents depends on
the actual type of mailbox used.

=examples

 print $folder->name;

=cut

sub name() {shift->{MB_foldername}}

#-------------------------------------------

=method writable

Checks whether the current folder is writable.

=examples

 $folder->addMessage($msg) if $folder->writable;

=cut

sub writable()  {shift->{MB_access} =~ /w|a/ }
sub writeable() {shift->writable}  # compatibility [typo]
sub readable()  {1}  # compatibility

#-------------------------------------------

=method update OPTIONS

Read new messages from the folder, which where received after opening
it.  This is quite dangerous and shouldn't be possible: folders which
are open are locked.  However, some applications do not use locks or
the wrong kind of locks.  This method reads the changes (not always
failsafe) and incorporates them in the open folder administration.

The OPTIONS are extra values which are passed to the
updateMessages() method which is doing the actual work here.

=cut

sub update(@)
{   my $self = shift;

    my @new  = $self->updateMessages
      ( trusted      => $self->{MB_trusted}
      , head_wrap    => $self->{MB_head_wrap}
      , head_type    => $self->{MB_head_type}
      , field_type   => $self->{MB_field_type}
      , message_type => $self->{MB_message_type}
      , body_delayed_type => $self->{MB_body_delayed_type}
      , head_delayed_type => $self->{MB_head_delayed_type}
      , @_
      );

    $self->log(PROGRESS => "Found ".@new." new messages in $self");
    $self;
}

#-------------------------------------------

=method organization

Returns whether a folder is organized as one 'FILE' with many messages or
a 'DIRECTORY' with one message per file.

=cut

sub organization() { shift->notImplemented }

#-------------------------------------------

=method modified [BOOLEAN]

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
    {    return $self->{MB_modified} = 1
            if $_->deleted || $_->modified;
    }

    0;
}

#-------------------------------------------

=method addMessage  MESSAGE

=method addMessages MESSAGE [, MESSAGE, ...]

Add a message to the folder.  A message is usually a Mail::Box::Message
object or a sub-class thereof.  The message shall not be in an other folder,
when you use this method.  In case it is, use moveMessage() or
copyMessage() via the manager.

Messages with id's which already exist in this folder are not added.

=examples

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
    {   # Do not add the same message twice, unless keep_dups.
        my $msgid = $message->messageId;

        unless($self->{MB_keep_dups})
        {   if(my $found = $self->messageId($msgid))
            {   $message->delete;
                return $found;
            }
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
    map {$self->addMessage($_)} @_;
}

#-------------------------------------------

=method copyTo FOLDER, OPTIONS

Copy the folder's messages to a new folder.  The new folder may be of
a different type.

=option  delete_copied BOOLEAN
=default delete_copied <false>

Flag the messages from the source folder to be deleted, just after it
was copied.  The deletion will only take effect when the originating
folder is closed.

=option  select 'ACTIVE'|'DELETED'|'ALL'|LABEL|!LABEL|FILTER
=default select 'ACTIVE'

Which messages are to be copied. See the description of the option
for the messages() method about how this works.

=option  subfolders BOOLEAN|'FLATTEN'|'RECURSE'
=default subfolders <folder type dependent>

How to handle sub-folders.  When false (0 or C<undef>), sub-folders
are simply ignored.  With 'FLATTEN', messages from sub-folders are
included in the main copy.  'RECURSE' recursively copies the
sub-folders as well.  By default, when the destination folder
supports sub-folders 'RECURSE' is used, otherwise 'FLATTEN'.  A value
of true will select the default.

=examples

 my $mgr  = Mail::Box::Manager->new;
 my $imap = $mgr->open(type => 'imap', host => ...);
 my $mh   = $mgr->open(type => 'mh', folder => '/tmp/mh',
     create => 1, access => 'w');

 $imap->copyTo($mh, delete_copied => 1);
 $mh->close; $imap->close;

=cut

sub copyTo($@)
{   my ($self, $to, %args) = @_;

    my $select      = $args{select} || 'ACTIVE';
    my $subfolders  = exists $args{subfolders} ? $args{subfolders} : 1;
    my $can_recurse
       = $to->can('openSubFolder') ne Mail::Box->can('openSubFolder');

    my ($flatten, $recurse)
       = $subfolders eq 'FLATTEN' ? (1, 0)
       : $subfolders eq 'RECURSE' ? (0, 1)
       : !$subfolders             ? (0, 0)
       : $can_recurse             ? (0, 1)
       :                            (1, 0);

    my $delete = $args{delete_copied} || 0;

    $self->_copy_to($to, $select, $flatten, $recurse, $delete);
}

# Interface may change without warning.
sub _copy_to($@)
{   my ($self, $to, @options) = @_;
    my ($select, $flatten, $recurse, $delete) = @options;

    $self->log(ERROR => "Destination folder $to is not writable."), return
        unless $to->writable;

    $self->log(PROGRESS => "Copying messages from $self to $to.");

    # Take messages from this folder.
    foreach my $msg ($self->messages($select))
    {   if($msg->copyTo($to)) { $msg->delete if $delete }
        else { $self->log(ERROR => "Copy failed.") }
    }

    return $self unless $flatten || $recurse;

    # Take subfolders
    foreach ($self->listSubFolders)
    {   my $subfolder = $self->openSubFolder($_);
        $self->log(ERROR => "Unable to open subfolder $_"), return
            unless defined $subfolder;

        if($flatten)   # flatten
        {    unless($subfolder->_copy_to($to, @options))
             {   $subfolder->close;
                 return;
             }
        }
        else           # recurse
        {    my $subto = $to->openSubFolder($_, create => 1, access => 'rw');
             unless($subto)
             {   $self->log(ERROR => "Unable to create subfolder $_ to $to");
                 $subfolder->close;
                 return;
             }

             unless($subfolder->_copy_to($subto, @options))
             {   $subfolder->close;
                 $subto->close;
                 return;
             }

             $subto->close;
        }

        $subfolder->close;
    }

    $self;
}

#-------------------------------------------

=head2 Closing the folder

=cut

#-------------------------------------------

=method close OPTIONS

lose the folder, optionally writing it. C<close> takes the same options as
write(), as well as a few others:

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

=option  write 'ALWAYS'|'NEVER'|'MODIFIED'
=default write 'MODIFIED'

Specifies whether the folder should be written.  As could be expected,
C<'ALWAYS'> means always (even if there are no changes), C<'NEVER'> means that
changes to the folder will be lost, and C<'MODIFIED'>
only saves the folder if there are any changes.

=option  force BOOLEAN
=default force <false>

Override the C<access> setting specified when the folder was opened. This
option only has an effect if its value is TRUE. NOTE: Writing to the folder
may not be permitted by the operating system, in which case even C<force> will
not help.

=cut

sub close(@)
{   my ($self, %args) = @_;
    my $force = $args{force} || 0;

    return if $self->{MB_is_closed};
    $self->{MB_is_closed} = 1;

    # Inform manager that the folder is closed.
    $self->{MB_manager}->close($self)
        if exists $self->{MB_manager} && !$args{close_by_manager};

    delete $self->{MB_manager};

    my $write;
    for($args{write} || 'MODIFIED')
    {   $write = $_ eq 'MODIFIED' ? $self->modified
               : $_ eq 'ALWAYS'   ? 1
               : $_ eq 'NEVER'    ? 0
               : croak "Unknown value to write options: $_.";
    }

    if($write && !$force && !$self->writable)
    {   $self->log(WARNING => "Changes not written to read-only folder $self.
Suggestion: \$folder->close(write => 'NEVER')");

        return 0;
    }

    my $rc = 1;
    if($write) { $rc = $self->write(force => $force) }
    else       { $self->{MB_messages} = [] }

    $self->{MB_locker}->unlock;
    $rc;
}

#-------------------------------------------

=method delete

Remove the specified folder file or folder directory (depending on
the type of folder) from disk.  Of course, THIS IS DANGEROUS: you "may"
lose data.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before deleting the source folder.  Otherwise you may lose
data if the system crashes or if there are software problems.

=examples

 my $folder = Mail::Box::Mbox->new(folder => 'InBox');
 $folder->delete;

=cut

sub delete()
{   my $self = shift;

    # Extra protection: do not remove read-only folders.
    unless($self->writable)
    {   $self->log(ERROR => "Folder $self not deleted: not writable.");
        $self->close(write => 'NEVER');
        return;
    }

    # Sub-directories need to be removed first.
    foreach ($self->listSubFolders)
    {   my $sub = $self->openRelatedFolder(folder => "$self/$_",access => 'rw');
        next unless defined $sub;
        $sub->delete;
    }

    $_->delete foreach $self->messages;

    $self->{MB_remove_empty} = 1;
    $self->close(write => 'ALWAYS');

    $self;
}

#-------------------------------------------

=method DESTROY

This method is called by Perl when an folder-object is no longer accessible
by the rest of the program.

=cut

sub DESTROY
{   my $self = shift;
    $self->close unless $self->inGlobalDestruction || $self->{MB_is_closed};
}

#-------------------------------------------

=head2 The messages

=cut

#-------------------------------------------

=method message INDEX [,MESSAGE]

Get or set a message with on a certain index.  Messages which are flagged
for deletion are counted.  Negative indexes start at the end of the folder.

=examples

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

=method messageId MESSAGE-ID [,MESSAGE]

With one argument, returns the message in the folder with the specified
MESSAGE-ID. If a reference to a message object is passed as the optional
second argument, the message is first stored in the folder, replacing any
existing message whose message ID is MESSAGE-ID. (The message ID of MESSAGE
need not match MESSAGE-ID.)

The MESSAGE-ID may still be in angles, which will be stripped.  In that
case blanks (which origin from header line folding) are removed too.  Other
info around the angles will be removed too.

WARNING: when the message headers are delay-parsed, the message might be in
the folder but not yet parsed into memory. In this case, use the find()
method instead of C<messageId> if you really need a thorough search.

=examples

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

    my $double = $self->{MB_msgid}{$msgid};
    if(defined $double && !$self->{MB_keep_dups})
    {   my $head1 = $message->head;
        my $head2 = $double->head;

        my $subj1 = $head1->get('subject') || '';
        my $subj2 = $head2->get('subject') || '';

        my $to1   = $head1->get('to') || '';
        my $to2   = $head2->get('to') || '';

        # Auto-delete doubles.
        return $message->delete
            if $subj1 eq $subj2 && $to1 eq $to2;

        $self->log(NOTICE => "Different message with id $msgid.");
        $msgid = $message->takeMessageId(undef);
    }

    $self->{MB_msgid}{$msgid} = $message;
}

sub messageID(@) {shift->messageId(@_)} # compatibility

#-------------------------------------------

=method find MESSAGE-ID

Like messageId(), this method searches for a message with the
MESSAGE-ID, returning the corresponding message object.  However, C<find>
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

=method messages ['ALL',RANGE,'ACTIVE','DELETED',LABEL,!LABEL,FILTER]

Returns multiple messages from the folder.  The default is 'ALL'
which will return (as expected maybe) all the messages in the
folder.  The 'ACTIVE' flag will return the messages not flagged for
deletion.  This is the opposite of 'DELETED', which returns all
messages from the folder which will be deleted when the folder is
closed.

You may also specify a RANGE: two numbers specifying begin and end
index in the array of messages.  Negative indexes count from the
end of the folder.  When an index is out-of-range, the returned
list will be shorter without complaints.

Everything else than the predefined names is seen as labels.  The messages
which have that label set will be returned.  When the sequence starts
with an exclamation mark (!), the search result is reversed.

For more complex searches, you can specify a FILTER, which is
simply a code reference.  The message is passed as only argument.

=examples

 foreach my $message ($folder->messages) {...}
 foreach my $message (@$folder) {...}
 my @messages   = $folder->messages;
 my @messages   = $folder->messages('ALL');    # same

 my $subset     = $folder->messages(10,-8);

 my @not_deleted= grep {not $_->deleted} $folder->messages;
 my @not_deleted= $folder->messages('ACTIVE'); # same

 my $nr_of_msgs = $folder->messages;           # scalar context
 $folder->[2];                  # third message, via overloading

 $mgr->moveMessages($spamfolder, $inbox->message('spam'));
 $mgr->moveMessages($archive, $inbox->message('seen'));

=cut

sub messages($;$)
{   my $self = shift;

    return @{$self->{MB_messages}} unless @_;
    my $nr = @{$self->{MB_messages}};

    if(@_==2)   # range
    {   my ($begin, $end) = @_;
        $begin += $nr if $begin < 0;
        $begin = 0    if $begin < 0;
        $end   += $nr if $end < 0;
        $end   = $nr  if $end > $nr;

        return $begin > $end ? () : @{$self->{MB_messages}}[$begin..$end];
    }

    my $what = shift;
    my $action
      = ref $what eq 'CODE'? $what
      : $what eq 'DELETED' ? sub {$_[0]->deleted}
      : $what eq 'ACTIVE'  ? sub {not $_[0]->deleted}
      : $what eq 'ALL'     ? sub {1}
      : $what =~ s/^\!//   ? sub {not $_[0]->label($what)}
      :                      sub {$_[0]->label($what)};

    grep {$action->($_)} @{$self->{MB_messages}};
}

#-------------------------------------------

=method messageIds

Returns a list of I<all> message-ids in the folder, including
those of messages which are to be deleted.

For some folder-types (like MH), this method may cause all message-files
to be read.  See their respective manual pages.

=examples

 foreach my $id ($folder->messageIds) {
    $folder->messageId($id)->print;
 }

=cut

sub messageIds()    { map {$_->messageId} shift->messages }
sub allMessageIds() {shift->messageIds}  # compatibility
sub allMessageIDs() {shift->messageIds}  # compatibility

#-------------------------------------------

=method current [NUMBER|MESSAGE|MESSAGE-ID]

Some mail-readers keep the I<current> message, which represents the last
used message.  This method returns [after setting] the current message.
You may specify a NUMBER, to specify that that message number is to be
selected as current, or a MESSAGE/MESSAGE-ID (as long as you are sure that the
header is already loaded, otherwise they are not recognized).

=examples

 $folder->current(0);
 $folder->current($message);

=cut

sub current(;$)
{   my $self = shift;
    return $self->{MB_current} || $self->message(-1)
        unless @_;

    my $next = shift;
    if(my $previous = $self->{MB_current})
    {    $previous->label(current => 0);
    }

    ($self->{MB_current} = $next)->label(current => 1);
    $next;
}

#-------------------------------------------

=method scanForMessages MESSAGE, MESSAGE-IDS, TIMESTAMP, WINDOW

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

=head2 Sub-folders

=cut

#-------------------------------------------

=method openSubFolder NAME, OPTIONS

Open (or create, if it does not exist yet) a new subfolder in an
existing folder.

=examples

 my $folder = Mail::Box::Mbox->new(folder => '=Inbox');
 my $sub    = $folder->openSubFolder('read');

=cut

sub openSubFolder(@) {shift->notImplemented}


#-------------------------------------------

=method listSubFolders OPTIONS

(Class and Instance method)
List the names of all sub-folders to this folder.  Use these names
in openSubFolder(), to open these folders on a mailbox type way.
For Mbox-folders, sub-folders are simulated.

=option  folder FOLDERNAME
=default folder <obligatory>

The folder whose sub-folders should be listed.

=option  folderdir DIRECTORY
=default folderdir <from folder>

=option  check BOOLEAN
=default check <false>

Specifies whether empty folders (folders which currently do not contain any
messages) should be included. It may not be useful to open empty folders, but 
saving to them is useful.

=option  skip_empty BOOL
=default skip_empty <false>

Shall empty folders (folders which currently do not contain any messages)
be included?  Empty folders are not useful to open, but may be useful
to save to.

=examples

 my $folder = $mgr->open('=in/new');
 my @subs = $folder->listSubFolders;

 my @subs = Mail::Box::Mbox->listSubFolders(folder => '=in/new');
 my @subs = Mail::Box::Mbox->listSubFolders; # toplevel folders.

=cut

sub listSubFolders(@) { () }

#-------------------------------------------

=method openRelatedFolder OPTIONS

Open a folder (usually a sub-folder) with the same options as this one.  If
there is a folder manager in use, it will be informed about this new folder.
OPTIONS overrule the options which where used for the folder this method
is called upon.

=cut

sub openRelatedFolder(@)
{   my $self    = shift;
    my @options = (@{$self->{MB_init_options}}, @_);

    $self->{MB_manager}
    ?  $self->{MB_manager}->open(@options)
    :  (ref $self)->new(@options);
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method read OPTIONS

Read messages from the folder into memory.  The OPTIONS are folder
specific.  Do not call C<read> yourself: it will be called for you
when you open the folder via the manager or instantiate a folder
object directly.

NOTE: if you are copying messages from one folder to another, use
addMessages() instead of C<read>.

=examples

 my $mgr = Mail::Box::Manager->new;
 my $folder = $mgr->open('InBox');             # implies read
 my $folder = Mail::Box::Mbox->new(folder => 'Inbox'); # same

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
      , field_type   => $self->{MB_field_type}
      , message_type => $self->{MB_message_type}
      , body_delayed_type => $self->{MB_body_delayed_type}
      , head_delayed_type => $self->{MB_head_delayed_type}
      , @_
      );

    if($self->{MB_modified})
    {   $self->log(INTERNAL => "Modified $self->{MB_modified}");
        $self->{MB_modified} = 0;  #after reading, no changes found yet.
    }

    # Which one becomes current?
    foreach ($self->messages)
    {   next unless $_->label('current') || 0;
        $self->current($_);
        last;
    }

    $self;
}

#-------------------------------------------

=method determineBodyType MESSAGE, HEAD

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

=method storeMessage MESSAGE

Store the message in the folder without the checks as performed by
addMessage().

=cut

sub storeMessage($)
{   my ($self, $message) = @_;

    push @{$self->{MB_messages}}, $message;
    $message->seqnr( @{$self->{MB_messages}} -1);
    $message;
}

#-------------------------------------------

=method lineSeparator [STRING|'CR'|'LF'|'CRLF']

Returns the character or characters used to separate lines in the folder
file, optionally after setting it to STRING, or one of the constants.
The first line of the folder sets the default.

UNIX uses a LF character, Mac a CR, and Windows both a CR and a LF.  Each
separator will be represented by a "\n" within your program.  However,
when processing platform foreign folders, complications appear.  Think about
the C<Size> field in the header.

When the separator is changed, the whole folder me be rewritten.  Although,
that may not be required.

=cut

my %seps = (CR => "\015", LF => "\012", CRLF => "\015\012");

sub lineSeparator(;$)
{   my $self = shift;
    return $self->{MB_linesep} unless @_;

   my $sep   = shift;
   $sep = $seps{$sep} if exists $seps{$sep};

   $self->{MB_linesep} = $sep;
   $_->lineSeparator($sep) foreach $self->messages;
   $sep;
}

#-------------------------------------------

=method write OPTIONS

Write the data to disk.  The folder is returned if successful. To write to a
different file, you must first create a new folder, then move the messages,
and then write the folder.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

=option  force BOOLEAN
=default force <false>

Override write-protection by the C<access> option while opening the folder
(whenever possible, it may still be blocked by the operating system).

=option  head_wrap INTEGER
=default head_wrap 72

=option  keep_deleted BOOLEAN
=default keep_deleted <false>

Do not remove messages which were flagged to be deleted from the folder
from memory, but do remove them from disk.

=option  save_deleted BOOLEAN
=default save_deleted <false>

Do also write messages which where flagged to be deleted to their folder.  The
flag is conserved (when possible), which means that the next write may
remove them for real.

=cut

sub write(@)
{   my ($self, %args) = @_;

    unless($args{force} || $self->writable)
    {   $self->log(ERROR => "Folder $self is opened read-only.\n");
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

    $self->{MB_messages} = \@keep;

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

=method coerce MESSAGE

Coerce the MESSAGE to be of the correct type to be placed in the
folder.  You are not may specify Mail::Internet and MIME::Entity
here: they will be translated into Mail::Message messages first.

=cut

sub coerce($)
{   my ($self, $message) = @_;
    $self->{MB_message_type}->coerce($message);
}


#-------------------------------------------

=method readMessages OPTIONS

Called by read() to actually read the messages from one specific
folder type.  The read() organizes the general activities.

The OPTIONS are C<trusted>, C<head_wrap>, C<head_type>, C<field_type>,
C<message_type>, C<body_delayed_type>, and C<head_delayed_type> as
defined by the folder at hand.  The defaults are the constructor
defaults (see new()).

=cut

sub readMessages(@) {shift->notImplemented}

#-------------------------------------------

=method updateMessages OPTIONS

Called by update() to read messages which arrived in the folder
after it was opened.  Sometimes, external applications dump messages
in a folder without locking (or using a different lock than your
application does).

Although this is quite a dangerous, it only fails when a folder is
updated (reordered or message removed) at exactly the same time as
new messages arrive.  These collisions are sparse.

The options are the same as for readMessages().

=cut

sub updateMessages(@) {shift}

#-------------------------------------------

=method writeMessages

Called by write() to actually write the messages from one specific
folder type.  The C<write> organizes the general activities.

=cut

sub writeMessages(@) {shift->notImplemented}

#-------------------------------------------

=method appendMessages OPTIONS

(Class method) Append one or more messages to an unopened folder.
Usually, this method is called by the Mail::Box::Manager (its method
appendMessage()), in which case the correctness of the
folder type is checked.

This method takes a list of labeled parameters, which may contain
any option which can be used when a folder is opened (most importantly
C<folderdir>).

=option  folder FOLDERNAME
=default folder <obligatory>

The name of the folder to which the messages are to be appended.  The folder
implementation will avoid opening the folder when possible, because this is
resource consuming.

=option  message MESSAGE
=default message undef

=option  messages ARRAY-OF-MESSAGES
=default messages undef

One reference to a MESSAGE or a reference to an ARRAY of MESSAGEs, which may
be of any type.  The messages will be first coerced into the correct
message type to fit in the folder, and then will be added to it.

=examples

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

=method locker

Returns the locking object.

=cut

sub locker() { shift->{MB_locker}}

#-------------------------------------------

=head2 Message threads [internals]

=cut

#-------------------------------------------

=method toBeThreaded MESSAGES

=method toBeUnthreaded MESSAGES

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

=head2 Other Methods

=cut

#-------------------------------------------

=method timespan2seconds TIME

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:
'1 hour' or '4 weeks'.

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
# Instance variables
# MB_access: new(access)
# MB_body_type: new(body_type)
# MB_coerce_opts: Options which have to be applied to the messages which
#    are coerced into this folder.
# MB_current: Used by some mailbox-types to save last read message.
# MB_field_type: new(field_type)
# MB_folderdir: new(folderdir)
# MB_foldername: new(folder)
# MB_head_type: new(head_type)
# MB_init_options: A copy of all the arguments given to the constructor
# MB_is_closed: Whether or not the mailbox is closed
# MB_extract: When to extract the body on the moment the header is read
# MB_keep_dups: new(keep_dups)
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

1;
