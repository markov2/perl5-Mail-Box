
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

Mail::Box - manage a mailbox, a folder with messages

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

Mail::Box is the base class for accessing various types of mailboxes (folders)
in a uniform manner.  The various folder types vary on how they store their
messages, but when some effort those differences could be hidden behind
a general API. For example, some folders store many messages in one single file,
where other store each message in a separate file withing the same directory.

No object in your program will be of type Mail::Box: it is only used as base
class for the real folder types.  Mail::Box is extended by

=over 4

=item * Mail::Box::Mbox

a folder type in which all related messages are stored in one file.  This
is very common folder type for UNIX.

=item * Mail::Box::MH

this folder creates a directory for each folder, and a message is one
file inside that directory.  The message files are numbered sequentially
on order of arrival.  A special C<.mh_sequences> file maintains flags
about the messages.

=item * Mail::Box::Maildir

maildir folders have a directory for each folder, although the first
implementation only supported one folder in total.  A folder directory
contains a C<tmp>, C<new>, and C<cur> subdirectory, each containting
messages with a different purpose.  New messages are created in C<tmp>,
then moved to C<new> (ready to be accepted).  Later, they are moved to
the C<cur> directory (accepted).  Each message is one file with a name
starting with timestamp.  The name also contains flags about the status
of the message.

=item * Mail::Box::POP3

Pop3 is a protocol which can be used to retreive messages from a
remote system.  After the connection to a POP server is made, the
messages can be looked at and removed as if they are on the local
system.

=back

Other folder types are on the (long) wishlist to get implemented.  Please,
help implementing more of them.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

Open a new folder. A list of labeled OPTIONS
for the mailbox can be supplied. Some options pertain to Mail::Box, and
others are added by sub-classes. The list below describes all the options
provided by any Mail::Box.

To control delay-loading of messages, as well the headers as the bodies,
a set of C<*_type> options are available. C<extract> determines whether
we want delay-loading.

=option  access MODE
=default access 'r'

Access-rights to the folder. MODE can be read-only (C<"r">), append (C<"a">),
and read-write (C<"rw">).  Folders are opened for read-only (C<"r">)
(which means write-protected) by default!

These MODEs have no relation to the modes actually used to open the
folder files within this module.  For instance, if you specify C<"rw">, and
open the folder, only read permission on the folder-file is required.

Be warned: writing a MBOX folder may create a new file to replace the
old folder.  The permissions and owner of the file get changed by this.

=option  create BOOLEAN
=default create <false>

Automatically create the folder when it does not exist yet.  This will only
work when access is granted for writing or appending to the folder.

Be careful: you may create a different folder type than you expect unless you
explicitly specify the C<type> (See Mail::Box::Manager::open(type)).

=option  folder FOLDERNAME
=default folder $ENV{MAIL}

Which folder to open (for reading or writing). When used for reading (the
C<access> option set to C<"r"> or C<"a">) the mailbox should already exist
and must be readable. The file or directory of the mailbox need not exist if it
is opened for reading and writing (C<"rw">).  Write-permission is checked when
opening an existing mailbox.

The folder name can be preceded by a C<"=">, to indicate that it is named
relative to the directory specified in new(folderdir).  Otherwise, it is
taken as relative or absolute path.

=option  folderdir DIRECTORY
=default folderdir undef

Where are folders to be found by default?  A folder-name may be preceded by
a equals-sign (C<=>, a C<mutt> convension) to explicitly state that the folder
is located below the default directory.  For example: in case
C<folderdir =E<gt> '/tmp'> and C<folder =E<gt> '=abc'>, the name of the
folder-file is C<'/tmp/abc'>.  Each folder type has already some default set.

=option  keep_dups BOOLEAN
=default keep_dups <false>

Indicates whether or not duplicate messages within the folder should          
be retained.  A message is considered to be a duplicate if its message-id      
is the same as a previously parsed message within the same folder. If this         
option is false (the default) such messages are automatically deleted,
because it is considered useless to store the same message twice.

=option  save_on_exit BOOLEAN
=default save_on_exit <true>

Sets the policy for saving the folder when it is closed.
A folder can be closed manually (see close()) or in a number of
implicit ways, including on the moment the program is terminated.

=option  remove_when_empty BOOLEAN
=default remove_when_empty <true>

Determines whether to remove the folder file or directory
automatically when the write would result in a folder without
messages nor sub-folders.

=option  trusted BOOLEAN
=default trusted <depends on folder location>

Flags whether to trust the data in the folder or not.  Folders which
reside in your C<folderdir> will be trusted by default (even when the
names if not specified staring with C<=>).  Folders which are outside
the folderdir or read from STDIN (Mail::Message::Construct::read()) are
not trused by default, and require some extra checking.

If you do not check encodings of received messages, you may print
binary data to the screen, which is a security risk.

=option  extract INTEGER | CODE | METHOD | 'LAZY'|'ALWAYS'
=default extract 10240

Defines when to parse (process) the content of the message.
When the header of a message is read, you may want to postpone the
reading of the body: header information is more often needed than
the body data, so why parse it always together?  The cost of delaying
is not too high, and with some luck you may never need parsing the body.

If you supply an INTEGER to this option, bodies of those messages with a
total size less than that number will be extracted from the folder only
when necessary.  Messages where the size (in the C<Content-Length> field)
is not included in the header, like often the case for multiparts and nested
messages, will not be extracted by default.

If you supply a CODE reference, that subroutine is called every time
that the extraction mechanism wants to determine whether to parse the
body or not. The subroutine is called with the following arguments:

 CODE->(FOLDER, HEAD)

where FOLDER is a reference to the folder we are reading.  HEAD refers to the
Mail::Message::Head::Complete head of the message at hand.  The routine must
return a C<true> value (extract now) or a C<false> value (be lazy, do not
parse yet).  Think about using the Mail::Message::guessBodySize() and
Mail::Message::guessTimestamp() on the header to determine your choice.

The third possibility is to specify the NAME of a method.  In that case,
for each message is called:

 FOLDER->NAME(HEAD)

Where each component has the same meaning as described above.

The fourth way to use this option involves constants: with C<'LAZY'>
all messages will be delayed. With C<'ALWAYS'> you enforce unconditional
parsing, no delaying will take place.  The latter is usuful when you are
sure you always need all the messages in the folder.

 $folder->new(extract => 'LAZY');  # Very lazy
 $folder->new(extract => 10000);   # Less than 10kB

 # same, but implemented yourself
 $folder->new(extract => &large);
 sub large($) {
    my ($f, $head) = @_;
    my $size = $head->guessBodySize;
    defined $size ? $size < 10000 : 1
 };

 # method call by name, useful for Mail::Box extensions
 # The example selects all messages sent by you to be loaded
 # without delay.  Other messages will be delayed.
 $folder->new(extract => 'sent_by_me');
 sub Mail::Box::send_by_me($) {
     my ($self, $header) = @_;
     $header->get('from') =~ m/\bmy\@example.com\b/i;
 }

=option  body_type CLASS|CODE
=default body_type <folder specific>

When messages are read from a folder-file, the headers will be stored in
a C<head_type> object.  For the body, however, there is a range of
choices about type, which are all described in the Mail::Message::Body
manual page.

Specify a CODE-reference which produces the body-type to be created, or
a CLASS of the body which is used when the body is not a multipart or
nested.  In case of a code reference, the header structure is passed as
first argument to the routine.

Do I<not> return a delayed body-type (like C<::Delayed>), because that is
determined by the C<extract> option while the folder is opened.  Even
delayed message will require some real body type when they get parsed
eventually.  Multiparts and nested messages are also outside your control.

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
C<'DotLock'>, C<'File'>, C<'Multi'>, C<'NFS'>, C<'POSIX'>, or C<'NONE'>.

=option  locker OBJECT
=default locker undef

An OBJECT which extends Mail::Box::Locker, and will handle folder locking
replacing the default lock behavior.

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

=option  fix_headers BOOLEAN
=default fix_headers <false>

Broken MIME headers usually stop the parser: all lines not parsed are
added to the body of the message.  With this flag set, the erroneous line
is added to the previous header field and parsing is continued.
See Mail::Box::Parser::Perl(fix_header_errors).

=error No folder name specified.

You did not specify the name of a folder to be opened.  Use the C<folder>
option or set the C<MAIL> environment variable.

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

    $self->read or return
        if $self->{MB_access} =~ /r|a/;

    $self;
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $class      = ref $self;
    my $foldername = $args->{folder} || $ENV{MAIL};
    unless($foldername)
    {   $self->log(ERROR => "No folder name specified.");
        return;
    }

    $self->{MB_foldername}   = $foldername;
    $self->{MB_init_options} = $args->{init_options};
    $self->{MB_coerce_opts}  = $args->{coerce_options} || [];
    $self->{MB_access}       = $args->{access}         || 'r';
    $self->{MB_remove_empty}
         = defined $args->{remove_when_empty} ? $args->{remove_when_empty} : 1;

    $self->{MB_save_on_exit}
         = defined $args->{save_on_exit} ? $args->{save_on_exit} : 1;

    $self->{MB_messages}     = [];
    $self->{MB_msgid}        = {};
    $self->{MB_organization} = $args->{organization}      || 'FILE';
    $self->{MB_linesep}      = "\n";
    $self->{MB_keep_dups}    = !$self->writable || $args->{keep_dups};
    $self->{MB_fix_headers}  = $args->{fix_headers};

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
    $self->{MB_field_type}          = $args->{field_type};

    my $headtype     = $self->{MB_head_type}
        = $args->{MB_head_type}     || 'Mail::Message::Head::Complete';

    my $extract  = $args->{extract} || 'extractDefault';
    $self->{MB_extract}
      = ref $extract eq 'CODE' ? $extract
      : $extract eq 'ALWAYS'   ? sub {1}
      : $extract eq 'LAZY'     ? sub {0}
      : $extract eq 'NEVER'    ? sub {1}  # compatibility
      : $extract =~ m/\D/      ? sub {no strict 'refs';shift->$extract(@_)}
      :     sub { my $size = $_[1]->guessBodySize;
                  defined $size && $size < $extract;
                };

    #
    # Create a locker.
    #

    $self->{MB_locker}
      = $args->{locker}
      || Mail::Box::Locker->new
          ( folder   => $self
          , method   => $args->{lock_type}
          , timeout  => $args->{lock_timeout}
          , wait     => $args->{lock_wait}
          , file     => ($args->{lockfile} || $args->{lock_file})
          );

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

=example

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

=c_method create FOLDERNAME, OPTIONS

Create a folder.  If the folder already exists, it will
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
 print "$folder";       # overloaded stringification

=cut

sub name() {shift->{MB_foldername}}

#-------------------------------------------

=method type

Returns a name for the type of mail box.  This can be C<mbox>, C<mh>,
C<maildir>, or C<pop3>.

=cut

sub type() {shift->notImplemented}

#-------------------------------------------

=method url

Represent the folder as a URL (Universal Resource Locator) string.  You may
pass such a URL as folder name to Mail::Box::Manager::open().

=example

 print $folder->url;
 # may result in
 #   mbox:/var/mail/markov   or
 #   pop3://user:password@pop.aol.com:101

=cut

sub url()
{   my $self = shift;
    $self->type . ':' . $self->name;
}

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

=method write OPTIONS

Write the data to disk.  The folder (a C<true> value) is returned if
successful.  Deleted messages are transformed into destroyed messages:
their memory is freed.

WARNING: When moving messages from one folder to another, be sure to write
(or close()) the destination folder before writing (or closing) the source
folder: otherwise you may lose data if the system crashes or if there are
software problems.

To write a folder to a different file, you must first create
a new folder, then move all the messages, and then write or close() that
new folder.

=option  force BOOLEAN
=default force <false>

Override write-protection by the C<access> option while opening the folder
(whenever possible, it may still be blocked by the operating system).

=option  save_deleted BOOLEAN
=default save_deleted <false>

Do also write messages which where flagged to be deleted to their folder.  The
flag for deletion is conserved (when possible), which means that a re-open of
the folder may remove the messages for real.  See close(save_deleted).

=error Folder $name is opened read-only

You can not write to this folder unless you have opened the folder to
write or append (see new(access)), or the C<force> option is set true.

=error Writing folder $name failed

For some reason (you probably got more error messages about this problem)
it is impossible to write the folder, although you should because there
were changes made.

=cut

sub write(@)
{   my ($self, %args) = @_;

    unless($args{force} || $self->writable)
    {   $self->log(ERROR => "Folder $self is opened read-only.\n");
        return;
    }

    my (@keep, @destroy);
    if($args{save_deleted}) {@keep = $self->messages }
    else
    {   foreach ($self->messages)
        {   if($_->isDeleted)
            {   push @destroy, $_;
                $_->diskDelete;
            }
            else {push @keep, $_}
        }
    }

    unless(@destroy || $self->isModified)
    {   $self->log(PROGRESS => "Folder $self not changed, so not updated.");
        return $self;
    }

    $args{messages} = \@keep;
    unless($self->writeMessages(\%args))
    {   $self->log(WARNING => "Writing folder $self failed.");
        return undef;
    }

    $self->modified(0);
    $self->{MB_messages} = \@keep;

    $self;
}

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

Returns how the folder is organized: as one C<'FILE'> with many messages,
a C<'DIRECTORY'> with one message per file, or by a C<'REMOTE'> server.

=cut

sub organization() { shift->notImplemented }

#-------------------------------------------

=method modified [BOOLEAN]

Sets whether the folder is modified or not.

=cut

sub modified(;$)
{   my $self = shift;
    return $self->isModified unless @_;   # compat 2.036

    return
      if $self->{MB_modified} = shift;    # force modified flag

    # unmodify all messages
    $_->modified(0) foreach $self->messages;
    0;
}

#-------------------------------------------

=method isModified

Checks if the folder is modified.  A folder is modified when any of the
messages is to be deleted, any of the messages has changed, or messages
are added after the folder was read from file.

=cut

sub isModified()
{   my $self     = shift;
    return 1 if $self->{MB_modified};

    foreach (@{$self->{MB_messages}})
    {    return $self->{MB_modified} = 1
            if $_->isDeleted || $_->isModified;
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

Which messages are to be copied. See messages(description)
about how this works.

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

=error Destination folder $name is not writable.

The folder where the messages are copied to is not opened with write
access (see new(access)).  This has no relation with write permission
to the folder which is controled by your operating system.

=error Copying failed for one message.

For some reason, for instance disc full, removed by external process, or
read-protection, it is impossible to copy one of the messages.  Copying will
proceed for the other messages.

=error Unable to create subfolder $name of $folder.

The copy includes the subfolders, but for some reason it was not possible
to copy one of these.  Copying will proceed for all other sub-folders.

=cut

sub copyTo($@)
{   my ($self, $to, %args) = @_;

    my $select      = $args{select} || 'ACTIVE';
    my $subfolders  = exists $args{subfolders} ? $args{subfolders} : 1;
    my $can_recurse = not $self->isa('Mail::Box::POP3');

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
        else { $self->log(ERROR => "Copying failed for one message.") }
    }

    return $self unless $flatten || $recurse;

    # Take subfolders
  SUBFOLDER:
    foreach ($self->listSubFolders)
    {   my $subfolder = $self->openSubFolder($_, access => 'r');
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
             {   $self->log(ERROR => "Unable to create subfolder $_ of $to");
                 next SUBFOLDER;
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

Close the folder, which usually implies writing the changes.  This will
return C<false> when writing is required but fails.  Please do check this
result.

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

=option  save_deleted BOOLEAN
=default save_deleted C<false>

Do also write messages which where flagged to be deleted to their folder.  The
flag for deletion is conserved (when possible), which means that a re-open of
the folder may remove the messages for real.  See write(save_deleted).

=example

 my $f = $mgr->open('spam', access => 'rw')
     or die "Cannot open spam: $!\n";

 $f->message(0)->delete
     if $f->messages;

 $f->close
     or die "Couldn't write $f: $!\n";

=warning Changes not written to read-only folder $self.

You have opened the folder read-only (which is the default, see new(access)),
made modifications, and now want to close it.  Set option C<force> if you
want to overrule the access mode, or close the folder with option
C<write> set to C<'NEVER'>.

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
    {   $write = $_ eq 'MODIFIED' ? $self->isModified
               : $_ eq 'ALWAYS'   ? 1
               : $_ eq 'NEVER'    ? 0
               : croak "Unknown value to folder->close(write => $_).";
    }

    if($write && !$force && !$self->writable)
    {   $self->log(WARNING => "Changes not written to read-only folder $self.
Suggestion: \$folder->close(write => 'NEVER')");

        return 0;
    }

    my $rc = !$write
          || $self->write
               ( force => $force
               , save_deleted => $args{save_deleted} || 0
               );

    $self->{MB_messages} = [];   # Boom!
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

=error Folder $name not deleted: not writable.

The folder must be opened with write access (see new(access)), otherwise
removing it will be refused.  So, you may have write-access according to
the operating system, but that will not automatically mean that this
C<delete> method permits you to.  The reverse remark is valid as well.

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

=warning Message-id '$msgid' does not contain a domain.

According to the RFCs, message-ids need to contain a unique random part,
then an C<@>, and then a domain name.  This is made to avoid the creation
of two messages with the same id.  The warning emerges when the C<@> is
missing from the string.

=warning Different messages with id $msgid.

The message id is discovered more than once within the same folder, but the
content of the message seems to be different.  This should not be possible:
each message must be unique.

=cut

sub messageId($;$)
{   my ($self, $msgid) = (shift, shift);

    if($msgid =~ m/\<([^>]+)\>/s )
    {   $msgid = $1;
        $msgid =~ s/\s//gs;

        $self->log(WARNING => "Message-id '$msgid' does not contain a domain.")
            unless index($msgid, '@') >= 0;
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

        $self->log(WARNING => "Different messages with id $msgid.");
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

sub find($)
{   my ($self, $msgid) = (shift, shift);
    my $msgids = $self->{MB_msgid};

    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }

    $self->scanForMessages(undef, $msgid, 'EVER', 'ALL')
        unless exists $msgids->{$msgid};

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

 my @not_deleted= grep {not $_->isDeleted} $folder->messages;
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
      : $what eq 'DELETED' ? sub {$_[0]->isDeleted}
      : $what eq 'ACTIVE'  ? sub {not $_[0]->isDeleted}
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

=example

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
it in the message thread, but which are not found yet because of the
lazy extraction if messages from file.  The folder is Scanned from
back to front, in search for the MESSAGE-IDS (which may be
one string or a reference to an array of strings).  The TIMESTAMP
and WINDOW (see option descriptions in new()) may limit the search.

This method returns the message-ids which were not found during the
scan.  Be warned that a message-id could already be known and therefore
not found: check that first.

=cut

sub scanForMessages($$$$)
{   my ($self, $startid, $msgids, $moment, $window) = @_;

    # Set-up msgid-list
    my %search = map {($_, 1)} ref $msgids ? @$msgids : $msgids;
    return () unless keys %search;

    # do not run on empty folder
    my $nr_messages = $self->messages
        or return keys %search; 

    # Set-up window-bound.
    my $bound;
    if($window eq 'ALL')
    {   $bound = 0;
    }
    elsif(defined $startid)
    {   my $startmsg = $self->messageId($startid);
        $bound = $startmsg->seqnr - $window if $startmsg;
        $bound = 0 if $bound < 0;
    }

    my $last = ($self->{MBM_last} || $nr_messages) -1;
    return keys %search if defined $bound && $bound > $last;

    # Set-up time-bound
    my $after = $moment eq 'EVER' ? 0 : $moment;

    while(!defined $bound || $last >= $bound)
    {   my $message = $self->message($last);
        my $msgid   = $message->messageId; # triggers load

        if(delete $search{$msgid})  # where we looking for this one?
        {    last unless keys %search;
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

=ci_method listSubFolders OPTIONS

List the names of all sub-folders to this folder, not recursively
decending.  Use these names as argument to openSubFolder(), to get
access to that folder.

For MBOX folders, sub-folders are simulated.

=option  folder FOLDERNAME
=default folder <obligatory>

The folder whose sub-folders should be listed.

=option  folderdir DIRECTORY
=default folderdir <from folder>

=option  check BOOLEAN
=default check <false>

Should all returned foldernames be checked to be sure that they are of
the right type?  Each sub-folder may need to be opened to check this,
with a folder type dependent penalty (in some cases very expensive).

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

sub listSubFolders(@) { () }   # by default no sub-folders

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

=method openSubFolder NAME, OPTIONS

Open (or create, if it does not exist yet) a new subfolder in an
existing folder.

=examples

 my $folder = Mail::Box::Mbox->new(folder => '=Inbox');
 my $sub    = $folder->openSubFolder('read');

=cut

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    $self->openRelatedFolder(@_, folder => "$self/$name");
}

#-------------------------------------------

=method nameOfSubfolder NAME

Returns the constructed name of the folder with NAME, which is a sub-folder
of this current one.

=cut

sub nameOfSubfolder($)
{   my ($self, $name)= @_;
    "$self/$name";
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

    return $self->{MB_body_delayed_type}
        if $self->{MB_lazy_permitted}
        && ! $message->isPart
        && ! $self->{MB_extract}->($self, $head);

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

=method coerce MESSAGE

Coerce the MESSAGE to be of the correct type to be placed in the
folder.  You can specify Mail::Internet and MIME::Entity objects
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

The OPTIONS are C<trusted>, C<head_type>, C<field_type>,
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

=method writeMessages OPTIONS

Called by write() to actually write the messages from one specific
folder type.  The C<write> organizes the general activities.  All options
to C<write> are passed to writeMessages as well.  Besides, a few extra
are added by C<write>.

=option  messages ARRAY
=default messages <required>

The messages to be written, which is a sub-set of all messages in the
current folder.

=cut

sub writeMessages(@) {shift->notImplemented}

#-------------------------------------------

=c_method appendMessages OPTIONS

Append one or more messages to an unopened folder.
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

The specified message is ready to be removed from a thread.
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

#-------------------------------------------

=method toBeUnthreaded MESSAGES

The specified message is ready to be included in a thread.
This will be passed on to the mail-manager, which keeps an overview on
which thread-detection objects are floating around.

=cut

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

=ci_method timespan2seconds TIME

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:
'1 hour' or '4 weeks'.

=error Invalid timespan '$timespan' specified.

The string does not follow the strict rules of the time span syntax which
is permitted as parameter.

=cut

sub timespan2seconds($)
{
    if( $_[1] =~ /^\s*(\d+\.?\d*|\.\d+)\s*(hour|day|week)s?\s*$/ )
    {     $2 eq 'hour' ? $1 * 3600
        : $2 eq 'day'  ? $1 * 86400
        :                $1 * 604800;  # week
    }
    else
    {   $_[0]->log(ERROR => "Invalid timespan '$_' specified.\n");
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
