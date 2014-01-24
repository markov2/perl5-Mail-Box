
use strict;
use warnings;

package Mail::Box;
use base 'Mail::Reporter';

use Mail::Box::Message;
use Mail::Box::Locker;
use File::Spec;

use Carp;
use Scalar::Util 'weaken';
use List::Util   qw/sum first/;
use Devel::GlobalDestruction 'in_global_destruction';

=chapter NAME

Mail::Box - manage a mailbox, a folder with messages

=chapter SYNOPSIS

 use M<Mail::Box::Manager>;
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
 foreach ($folder->messages) {...} # all messages
 foreach (@$folder) {...}          # all messages

 $folder->addMessage(M<Mail::Box::Message>->new(...));

Tied-interface:

 tie my(@inbox), 'M<Mail::Box::Tie::ARRAY>', $inbox;

 # Four times the same:
 $inbox[3]->print;                 # tied
 $folder->[3]->print;              # overloaded folder
 $folder->message(3)->print;       # usual
 print $folder->[3];               # overloaded message

 tie my(%inbox), 'M<Mail::Box::Tie::HASH>', $inbox;

 # Twice times the same
 $inbox{$msgid}->print;            # tied
 $folder->messageId($msgid)->print;# usual

=chapter DESCRIPTION

A M<Mail::Box::Manager> creates C<Mail::Box> objects.  But you already
knew, because you started with the M<Mail::Box-Overview> manual page.
That page is obligatory reading, sorry!

C<Mail::Box> is the base class for accessing various types of mailboxes
(folders) in a uniform manner.  The various folder types vary on how
they store their messages, but when some effort those differences could
be hidden behind a general API. For example, some folders store many
messages in one single file, where other store each message in a separate
file withing the same directory.

No object in your program will be of type C<Mail::Box>: it is only used
as base class for the real folder types.  C<Mail::Box> is extended by


=cut

#-------------------------------------------

=chapter OVERLOADED

=overload @{}

When the folder is used as if it is a reference to an array, it will
show the messages, like M<messages()> and M<message()> would do.

=examples use overloaded folder as array

 my $msg = $folder->[3];
 my $msg = $folder->message(3);          # same

 foreach my $msg (@$folder) ...
 foreach my $msg ($folder->messages) ... # same

=overload ""

(stringification)
The folder objects stringify to their name.  This simplifies especially
print statements and sorting a lot.

=example use overloaded folder as string

 # Three lines with overloading: resp. cmp, @{}, and ""
 foreach my $folder (sort @folders)
 {   my $msgcount = @$folder;
     print "$folder contains $msgcount messages\n";
 }

=overload cmp

(string comparison) folders are compared based on their name.  The sort
rules are those of the build-in C<cmp>.

=cut

use overload '@{}' => sub { shift->{MB_messages} }
           , '""'  => 'name'
           , 'cmp' => sub {$_[0]->name cmp "${_[1]}"};

#-------------------------------------------

=chapter METHODS

=section Constructors

=c_method new %options
Open a new folder. A list of labeled %options for the mailbox can be
supplied. Some options pertain to Mail::Box, and others are added by
sub-classes.

To control delay-loading of messages, as well the headers as the bodies,
a set of C<*_type> options are available. C<extract> determines whether
we want delay-loading.

=option  access MODE
=default access C<'r'>
Access-rights to the folder.  Folders are opened for read-only (which
means write-protected) by default! MODE can be
=over 4
=item C<'r'>: read-only (default)
=item C<'a'>: append
=item C<'rw'>: read-write
=item C<'d'>: delete
=back

These MODE has no relation to the modes actually used to open the folder
files within this module.  For instance, if you specify C<"rw">, and
open the folder, only read permission on the folder-file is required.

Be warned: writing a MBOX folder may create a new file to replace the old
folder.  The permissions and owner of the file may get changed by this.

=option  create BOOLEAN
=default create <false>
Automatically create the folder when it does not exist yet.  This will only
work when access is granted for writing or appending to the folder.

Be careful: you may create a different folder type than you expect unless you
explicitly specify M<Mail::Box::Manager::open(type)>.

=option  folder FOLDERNAME
=default folder C<$ENV{MAIL}>
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
A folder can be closed manually (see M<close()>) or in a number of
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
the folderdir or read from STDIN (M<Mail::Message::Construct::read()>) are
not trused by default, and require some extra checking.

If you do not check encodings of received messages, you may print
binary data to the screen, which is a security risk.

=option  extract INTEGER | CODE | METHOD | 'LAZY'|'ALWAYS'
=default extract C<10240>

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
M<Mail::Message::Head::Complete> head of the message at hand.  The routine must
return a C<true> value (extract now) or a C<false> value (be lazy, do not
parse yet).  Think about using the M<Mail::Message::Head::guessBodySize()> and
M<Mail::Message::guessTimestamp()> on the header to determine your choice.

The third possibility is to specify the NAME of a method.  In that case,
for each message is called:

 FOLDER->NAME(HEAD)

Where each component has the same meaning as described above.

The fourth way to use this option involves constants: with C<LAZY>
all messages will be delayed. With C<ALWAYS> you enforce unconditional
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

 # method call by name, useful for Mail::Box
 # extensions. The example selects all messages
 # sent by you to be loaded without delay.
 # Other messages will be delayed.
 $folder->new(extract => 'sent_by_me');
 sub Mail::Box::send_by_me($) {
     my ($self, $header) = @_;
     $header->get('from') =~ m/\bmy\@example.com\b/i;
 }

=option  body_type CLASS|CODE
=default body_type <folder specific>
When messages are read from a folder-file, the headers will be stored in
a C<head_type> object.  For the body, however, there is a range of
choices about type, which are all described in M<Mail::Message::Body>.

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
is M<Mail::Message::Body::Lines>.  Please check the applicable
manual pages.

=option  multipart_type CLASS
=default multipart_type M<Mail::Message::Body::Multipart>
The default type of objects which are to be created for multipart message
bodies.

=option  body_delayed_type CLASS
=default body_delayed_type M<Mail::Message::Body::Delayed>
The bodies which are delayed: which will be read from file when it
is needed, but not before.

=option  coerce_options ARRAY
=default coerce_options C<[]>
Keep configuration information for messages which are coerced into the
specified folder type, starting with a different folder type (or even
no folder at all).
Messages which are coerced are always fully read, so this kind of information
does not need to be kept here.

=option  field_type CLASS
=default field_type undef
The type of the fields to be used in a header. Must extend
M<Mail::Message::Field>.

=option  head_type CLASS
=default head_type M<Mail::Message::Head::Complete>
The type of header which contains all header information.  Must extend
M<Mail::Message::Head::Complete>.

=option  head_delayed_type CLASS
=default head_delayed_type M<Mail::Message::Head::Delayed>
The headers which are delayed: which will be read from file when it
is needed, but not before.

=option  lock_type CLASS|STRING|ARRAY
=default lock_type M<Mail::Box::Locker::DotLock>
The type of the locker object.  This may be the full name of a CLASS
which extends Mail::Box::Locker, or one of the known locker types
C<DotLock>, C<Flock>, C<Mutt>, C<NFS>, C<POSIX>, or C<NONE>.  If an ARRAY
is specified, then a Multi locker is built which uses the specified list.

=option  locker OBJECT
=default locker undef
An OBJECT which extends M<Mail::Box::Locker>, and will handle folder locking
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
M<Mail::Box::Manager> instance.

=option  message_type CLASS
=default message_type <folder-class>::Message
What kind of message objects are stored in this type of folder.  The
default is constructed from the folder class followed by C<::Message>.
For instance, the message type for C<Mail::Box::POP3> is
C<Mail::Box::POP3::Message>

=option  fix_headers BOOLEAN
=default fix_headers <false>
Broken MIME headers usually stop the parser: all lines not parsed are
added to the body of the message.  With this flag set, the erroneous line
is added to the previous header field and parsing is continued.
See M<Mail::Box::Parser::Perl::new(fix_header_errors)>.

=error No folder name specified.
You did not specify the name of a folder to be opened.  Use the
M<new(folder)> option or set the C<MAIL> environment variable.

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

    my %args = @_;
    weaken $args{manager};   # otherwise, the manager object may live too long

    my $self = $class->SUPER::new
      ( @_
      , init_options => \%args     # for clone
      ) or return;

    $self->read or return
        if $self->{MB_access} =~ /r|a/;

    $self;
}

sub init($)
{   my ($self, $args) = @_;

    return unless defined $self->SUPER::init($args);

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
      : !defined $folderdir                            ? 0
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
        = $args->{head_type}        || 'Mail::Message::Head::Complete';

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
          , expires  => $args->{lock_wait}
          , file     => ($args->{lockfile} || $args->{lock_file})
          , $self->logSettings
          );

    $self;
}

#-------------------------------------------

=section The folder

=method folderdir [$directory]
Get or set the $directory which is used to store mail-folders by default.

=examples
 print $folder->folderdir;
 $folder->folderdir("$ENV{HOME}/nsmail");

=cut

sub folderdir(;$)
{   my $self = shift;
    $self->{MB_folderdir} = shift if @_;
    $self->{MB_folderdir};
}

sub foundIn($@) { shift->notImplemented }

=method name
Returns the name of the folder.  What the name represents depends on
the actual type of mailbox used.

=examples
 print $folder->name;
 print "$folder";       # overloaded stringification
=cut

sub name() {shift->{MB_foldername}}

=method type
Returns a name for the type of mail box.  This can be C<mbox>, C<mh>,
C<maildir>, or C<pop3>.
=cut

sub type() {shift->notImplemented}

=method url
Represent the folder as a URL (Universal Resource Locator) string.  You may
pass such a URL as folder name to M<Mail::Box::Manager::open()>.

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

=method size
Returns the size of the folder in bytes, not counting in the deleted
messages.  The error in the presented result may be as large as 10%,
because the in-memory representation of messages is not always the
same as the size when they are written.
=cut

sub size() { sum map { $_->size } shift->messages('ACTIVE') }

=method update %options
Read new messages from the folder, which where received after opening
it. This is quite dangerous and shouldn't be possible: folders which
are open are locked. However, some applications do not use locks or the
wrong kind of locks. This method reads the changes (not always failsafe)
and incorporates them in the open folder administration.

The %options are extra values which are passed to the
M<updateMessages()> method which is doing the actual work here.
=cut

sub update(@)
{   my $self = shift;

    $self->updateMessages
      ( trusted      => $self->{MB_trusted}
      , head_type    => $self->{MB_head_type}
      , field_type   => $self->{MB_field_type}
      , message_type => $self->{MB_message_type}
      , body_delayed_type => $self->{MB_body_delayed_type}
      , head_delayed_type => $self->{MB_head_delayed_type}
      , @_
      );

    $self;
}

=method organization
Returns how the folder is organized: as one C<FILE> with many messages,
a C<DIRECTORY> with one message per file, or by a C<REMOTE> server.
=cut

sub organization() { shift->notImplemented }

=method addMessage $message, %options
Add a message to the folder.  A message is usually a
M<Mail::Box::Message> object or a sub-class thereof.  The message
shall not be in an other folder, when you use this method.
In case it is, use M<Mail::Box::Manager::moveMessage()> or
M<Mail::Box::Manager::copyMessage()> via the manager.

Messages with id's which already exist in this folder are not added.

BE WARNED that message labels may get lost when a message is moved from
one folder type to an other.  An attempt is made to translate labels,
but there are many differences in interpretation by applications.

=option  share BOOLEAN
=default share <not used>
Try to share the physical resource of the current message with the
indicated message.  It is sometimes possible to share messages between
different folder types.  When the sharing is not possible, than this
option is simply ignored.

Sharing the resource is quite dangerous, and only available for a
limited number of folder types, at the moment only some M<Mail::Box::Dir>
folders; these file-based messages can be hardlinked (on platforms that
support it).  The link may get broken when one message is modified in one
of the folders.... but maybe not, depending on the folder types involved.

=examples
 $folder->addMessage($msg);
 $folder->addMessages($msg1, $msg2, ...);

=cut

sub addMessage($@)
{   my $self    = shift;
    my $message = shift or return $self;
    my %args    = @_;

    confess <<ERROR if $message->can('folder') && defined $message->folder;
You cannot add a message which is already part of a folder to a new
one.  Please use moveTo or copyTo.
ERROR

    # Force the message into the right folder-type.
    my $coerced = $self->coerce($message);
    $coerced->folder($self);

    unless($coerced->head->isDelayed)
    {   # Do not add the same message twice, unless keep_dups.
        my $msgid = $coerced->messageId;

        unless($self->{MB_keep_dups})
        {   if(my $found = $self->messageId($msgid))
            {   $coerced->label(deleted => 1);
                return $found;
            }
        }

        $self->messageId($msgid, $coerced);
        $self->toBeThreaded($coerced);
    }

    $self->storeMessage($coerced);
    $coerced;
}

=method addMessages @messages
Adds a set of message objects to the open folder at once.  For some folder
types this may be faster than adding them one at a time.

=examples
 $folder->addMessages($msg1, $msg2, ...);
=cut

sub addMessages(@)
{   my $self = shift;
    map $self->addMessage($_), @_;
}

=method copyTo $folder, %options
Copy the folder's messages to a new folder.  The new folder may be of
a different type.

=option  delete_copied BOOLEAN
=default delete_copied <false>

Flag the messages from the source folder to be deleted, just after it
was copied.  The deletion will only take effect when the originating
folder is closed.

=option  select 'ACTIVE'|'DELETED'|'ALL'|LABEL|!LABEL|FILTER
=default select 'ACTIVE'

Which messages are to be copied. See the description of M<messages()>
about how this works.

=option  subfolders BOOLEAN|'FLATTEN'|'RECURSE'
=default subfolders <folder type dependent>

How to handle sub-folders.  When false (C<0> or C<undef>), sub-folders
are simply ignored.  With C<FLATTEN>, messages from sub-folders are
included in the main copy.  C<RECURSE> recursively copies the
sub-folders as well.  By default, when the destination folder
supports sub-folders C<RECURSE> is used, otherwise C<FLATTEN>.  A value
of true will select the default.

=option  share      BOOLEAN
=default share      <not used>
Try to share the message between the folders.  Some M<Mail::Box::Dir>
folder types do support it by creating a hardlink (on UNIX/Linux).

=examples

 my $mgr  = Mail::Box::Manager->new;
 my $imap = $mgr->open(type => 'imap', host => ...);
 my $mh   = $mgr->open(type => 'mh', folder => '/tmp/mh',
     create => 1, access => 'w');

 $imap->copyTo($mh, delete_copied => 1);
 $mh->close; $imap->close;

=error Destination folder $name is not writable.
The folder where the messages are copied to is not opened with write
access (see M<new(access)>).  This has no relation with write permission
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
    my $share  = $args{share}         || 0;

    $self->_copy_to($to, $select, $flatten, $recurse, $delete, $share);
}

# Interface may change without warning.
sub _copy_to($@)
{   my ($self, $to, @options) = @_;
    my ($select, $flatten, $recurse, $delete, $share) = @options;

    $self->log(ERROR => "Destination folder $to is not writable."),
        return unless $to->writable;

    # Take messages from this folder.
    my @select = $self->messages($select);
    $self->log(PROGRESS =>
        "Copying ".@select." messages from $self to $to.");

    foreach my $msg (@select)
    {   if($msg->copyTo($to, share => $share))
             { $msg->label(deleted => 1) if $delete }
        else { $self->log(ERROR => "Copying failed for one message.") }
    }

    return $self unless $flatten || $recurse;

    # Take subfolders

  SUBFOLDER:
    foreach ($self->listSubFolders(check => 1))
    {   my $subfolder = $self->openSubFolder($_, access => 'r');
        $self->log(ERROR => "Unable to open subfolder $_"), next
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

=method close %options

Close the folder, which usually implies writing the changes.  This will
return C<false> when writing is required but fails.  Please do check this
result.

WARNING: When moving messages from one folder to another, be sure to
write the destination folder before writing and closing the source
folder.  Otherwise you may lose data if the system crashes or if there
are software problems.

=option  write 'ALWAYS'|'NEVER'|'MODIFIED'
=default write C<MODIFIED>

Specifies whether the folder should be written.  As could be expected,
C<ALWAYS> means always (even if there are no changes), C<NEVER> means
that changes to the folder will be lost, and C<MODIFIED> only saves the
folder if there are any changes.

=option  force BOOLEAN
=default force <false>

Override the M<new(access)> setting which was specified when the folder
was opened. This option only has an effect if its value is TRUE. NOTE:
Writing to the folder may not be permitted by the operating system,
in which case even C<force> will not help.

=option  save_deleted BOOLEAN
=default save_deleted C<false>

Do also write messages which where flagged to be deleted to their folder.  The
flag for deletion is conserved (when possible), which means that a re-open of
the folder may remove the messages for real.  See M<write(save_deleted)>.

=example

 my $f = $mgr->open('spam', access => 'rw')
     or die "Cannot open spam: $!\n";

 $f->message(0)->delete
     if $f->messages;

 $f->close
     or die "Couldn't write $f: $!\n";

=warning Changes not written to read-only folder $self.

You have opened the folder read-only --which is the default set
by M<new(access)>--, made modifications, and now want to close it.
Set M<close(force)> if you want to overrule the access mode, or close
the folder with M<close(write)> set to C<NEVER>.

=cut

sub close(@)
{   my ($self, %args) = @_;
    my $force = $args{force} || 0;

    return 1 if $self->{MB_is_closed};
    $self->{MB_is_closed}++;

    # Inform manager that the folder is closed.
    my $manager = delete $self->{MB_manager};
    $manager->close($self, close_by_self =>1)
        if defined $manager && !$args{close_by_manager};

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
        $self->locker->unlock;
        $self->{MB_messages} = [];    # Boom!
        return 0;
    }

    my $rc = !$write
          || $self->write
               ( force => $force
               , save_deleted => $args{save_deleted} || 0
               );

    $self->locker->unlock;
    $self->{MB_messages} = [];                  # Boom!
    $rc;
}

=method delete %options
Remove the specified folder file or folder directory (depending on
the type of folder) from disk.  Of course, THIS IS DANGEROUS: you "may"
lose data.  Returns a C<true> value on success.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before deleting the source folder.  Otherwise you may lose
data if the system crashes or if there are software problems.

=option  recursive BOOLEAN
=default recursive 1

=example removing an open folder
 my $folder = Mail::Box::Mbox->new(folder => 'InBox', access => 'rw');
 ... some other code ...
 $folder->delete;

=example removing an closed folder
 my $folder = Mail::Box::Mbox->new(folder => 'INBOX', access => 'd');
 $folder->delete;

=error Folder $name not deleted: not writable.
The folder must be opened with write access via M<new(access)>, otherwise
removing it will be refused.  So, you may have write-access according to
the operating system, but that will not automatically mean that this
C<delete> method permits you to.  The reverse remark is valid as well.

=cut

sub delete(@)
{   my ($self, %args) = @_;
    my $recurse = exists $args{recursive} ? $args{recursive} : 1;

    # Extra protection: do not remove read-only folders.
    unless($self->writable)
    {   $self->log(ERROR => "Folder $self not deleted: not writable.");
        $self->close(write => 'NEVER');
        return;
    }

    # Sub-directories need to be removed first.
    if($recurse)
    {   foreach ($self->listSubFolders)
        {   my $sub = $self->openRelatedFolder
               (folder => "$self/$_", access => 'd', create => 0);
            defined $sub && $sub->delete(%args);
        }
    }

    $self->close(write => 'NEVER');
    $self;
}

#-------------------------------------------

=c_method appendMessages %options

Append one or more messages to an unopened folder.
Usually, this method is called by the M<Mail::Box::Manager::appendMessage()>,
in which case the correctness of the folder type is checked.

For some folder types it is required to open the folder before it can
be used for appending.  This can be fast, but this can also be very
slow (depends on the implementation).  All %options passed will also be
used to open the folder, if needed.

=requires folder FOLDERNAME

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

=option  share BOOLEAN
=default share <false>
Try to share physical storage of the message.  Only available for a
limited number of folder types, otherwise no-op.

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

=section Folder flags

=method writable
Checks whether the current folder is writable.

=examples
 $folder->addMessage($msg) if $folder->writable;

=cut

sub writable()  {shift->{MB_access} =~ /w|a|d/ }
sub writeable() {shift->writable}  # compatibility [typo]
sub readable()  {1}  # compatibility

=method access
Returns the access mode of the folder, as set by M<new(access)>
=cut

sub access()    {shift->{MB_access}}

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

=method isModified
Checks if the folder, as stored in memory, is modified.  A true value is
returned when any of the messages is to be deleted, has changed, or messages
were added after the folder was read from file.

WARNING: this flag is not related to an external change to the folder
structure on disk.  Have a look at M<update()> for that.

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

=section The messages

=method message $index, [$message]
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

=method messageId $message_id, [$message]

With one argument, returns the message in the folder with the specified
$message_id. If a reference to a message object is passed as the optional
second argument, the message is first stored in the folder, replacing any
existing message whose message ID is $message_id. (The message ID of $message
need not match $message_id.)

!!WARNING!!: when the message headers are delay-parsed, the message
might be in the folder but not yet parsed into memory. In this case, use
M<find()> instead of C<messageId()> if you really need a thorough search.
This is especially the case for directory organized folders without
special indexi, like M<Mail::Box::MH>.

The $message_id may still be in angles, which will be stripped.  In that
case blanks (which origin from header line folding) are removed too.  Other
info around the angles will be removed too.

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

=warning Different messages with id $msgid
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
        return $message->label(deleted => 1)
            if $subj1 eq $subj2 && $to1 eq $to2;

        $self->log(WARNING => "Different messages with id $msgid");
        $msgid = $message->takeMessageId(undef);
    }

    $self->{MB_msgid}{$msgid} = $message;
    weaken($self->{MB_msgid}{$msgid});
    $message;
}

sub messageID(@) {shift->messageId(@_)} # compatibility

=method find $message_id
Like M<messageId()>, this method searches for a message with the
$message_id, returning the corresponding message object.  However, C<find>
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
    else
    {   # Illegal message-id
        $msgid =~ s/\s/+/gs;
    }

    $self->scanForMessages(undef, $msgid, 'EVER', 'ALL')
        unless exists $msgids->{$msgid};

    $msgids->{$msgid};
}

=method messages <'ALL'|$range|'ACTIVE'|'DELETED'|$label| !$label|$filter>

Returns multiple messages from the folder.  The default is C<ALL>
which will return (as expected maybe) all the messages in the
folder.  The C<ACTIVE> flag will return the messages not flagged for
deletion.  This is the opposite of C<DELETED>, which returns all
messages from the folder which will be deleted when the folder is
closed.

You may also specify a $range: two numbers specifying begin and end
index in the array of messages.  Negative indexes count from the
end of the folder.  When an index is out-of-range, the returned
list will be shorter without complaints.

Everything else than the predefined names is seen as labels.  The messages
which have that label set will be returned.  When the sequence starts
with an exclamation mark (!), the search result is reversed.

For more complex searches, you can specify a $filter, which is
simply a code reference.  The message is passed as only argument.

=examples

 foreach my $message ($folder->messages) {...}
 foreach my $message (@$folder) {...}

 # twice the same
 my @messages   = $folder->messages;
 my @messages   = $folder->messages('ALL');

 # Selection based on a range (begin, end)
 my $subset     = $folder->messages(10,-8);

 # twice the same:
 my @not_deleted= grep {not $_->isDeleted}
                     $folder->messages;
 my @not_deleted= $folder->messages('ACTIVE');

 # scalar context the number of messages
 my $nr_of_msgs = $folder->messages;

 # third message, via overloading
 $folder->[2];

 # Selection based on labels
 $mgr->moveMessages($spam, $inbox->message('spam'));
 $mgr->moveMessages($archive, $inbox->message('seen'));

=cut

sub messages($;$)
{   my $self = shift;

    return @{$self->{MB_messages}} unless @_;
    my $nr = @{$self->{MB_messages}};

    if(@_==2)   # range
    {   my ($begin, $end) = @_;
        $begin += $nr   if $begin < 0;
        $begin  = 0     if $begin < 0;
        $end   += $nr   if $end < 0;
        $end    = $nr-1 if $end >= $nr;

        return () if $begin > $end;

        my @range = @{$self->{MB_messages}}[$begin..$end];
        return @range;
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

=method nrMessages %options
Simply calls M<messages()> in scalar context to return a count instead
of the messages itself.  Some people seem to understand this better.
Note that nrMessages() will default to returning a count of
C<ALL> messages in the folder, including both C<ACTIVE> and C<DELETED>.

The %options are passed to (and explained in) M<messages()>.
=cut

sub nrMessages(@) { scalar shift->messages(@_) }

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

=method current [$number|$message|$message_id]
Some mail-readers keep the I<current> message, which represents the last
used message.  This method returns [after setting] the current message.
You may specify a $number, to specify that that message number is to be
selected as current, or a $message/$message_id (as long as you are sure
that the header is already loaded, otherwise they are not recognized).

=examples
 $folder->current(0);
 $folder->current($message);
=cut

sub current(;$)
{   my $self = shift;

    unless(@_)
    {   return $self->{MB_current}
           if exists $self->{MB_current};
	
        # Which one becomes current?
	my $current
	  = $self->findFirstLabeled(current => 1)
	 || $self->findFirstLabeled(seen    => 0)
	 || $self->message(-1)
	 || return undef;

        $current->label(current => 1);
        $self->{MB_current} = $current;
	return $current;
    }

    my $next = shift;
    if(my $previous = $self->{MB_current})
    {    $previous->label(current => 0);
    }

    ($self->{MB_current} = $next)->label(current => 1);
    $next;
}

=method scanForMessages $message, $message_ids, $timespan, $window

You start with a $message, and are looking for a set of messages
which are related to it.  For instance, messages which appear in
the 'In-Reply-To' and 'Reference' header fields of that message.
These messages are known by their $message_ids and you want to find
them in the folder.

When all message-ids are known, then looking-up messages is simple:
they are found in a plain hash using M<messageId()>.  But Mail::Box
is lazy where it can, so many messages may not have been read from
file yet, and that's the preferred situation, because that saves
time and memory.

It is not smart to search for the messages from front to back in
the folder: the chances are much higher that related message
reside closely to each other.  Therefore, this method starts
scanning the folder from the specified $message, back to the front
of the folder.

The $timespan can be used to terminate the search based on the time
enclosed in the message.  When the constant string C<EVER> is used as
$timespan, then the search is not limited by that.  When an integer
is specified, it will be used as absolute time in time-ticks as
provided by your platform dependent C<time> function.  In other cases,
it is passed to M<timespan2seconds()> to determine the threshold
as time relative to the message's time.

The $window is used to limit the search in number of messages to be
scanned as integer or constant string C<ALL>.

Returned are the message-ids which were not found during the scan.
Be warned that a message-id could already be known and therefore not
found: check that first.

=example scanning through a folder for a message
 my $refs   = $msg->get('References') or return;
 my @msgids = $ref =~ m/\<([^>]+\>/g;
 my @failed = $folder->scanForMessages($msg, \@msgids, '3 days', 50);
=cut

sub scanForMessages($$$$)
{   my ($self, $startid, $msgids, $moment, $window) = @_;

    # Set-up msgid-list
    my %search = map +($_ => 1), ref $msgids ? @$msgids : $msgids;
    return () unless keys %search;

    # do not run on empty folder
    my $nr_messages = $self->messages
        or return keys %search; 

    my $startmsg = defined $startid ? $self->messageId($startid) : undef;

    # Set-up window-bound.
    my $bound = 0;
    if($window ne 'ALL' && defined $startmsg)
    {   $bound = $startmsg->seqnr - $window;
        $bound = 0 if $bound < 0;
    }

    my $last = ($self->{MBM_last} || $nr_messages) -1;
    return keys %search if defined $bound && $bound > $last;

    # Set-up time-bound
    my $after = $moment eq 'EVER'   ? 0
              : $moment =~ m/^\d+$/ ? $moment
              : !$startmsg          ? 0
              : $startmsg->timestamp - $self->timespan2seconds($moment);

    while($last >= $bound)
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

=method findFirstLabeled $label, [BOOLEAN, [$msgs]]
Find the first message which has this $label with the correct setting. The
BOOLEAN indicates whether any true value or any false value is to be
found in the ARRAY of $msgs.  By default, a true value is searched for.
When a message does not have the requested label, it is taken as false.

=examples looking for a labeled message
 my $current = $folder->findFirstLabeled('current');

 my $first   = $folder->findFirstLabeled(seen => 0);

 my $last    = $folder->findFirstLabeled(seen => 0,
                 [ reverse $self->messages('ACTIVE') ] )
                 
=cut

sub findFirstLabeled($;$$)
{   my ($self, $label, $set, $msgs) = @_;

    if(!defined $set || $set)
    {   my $f = first { $_->label($label) }
           (defined $msgs ? @$msgs : $self->messages);
    }
    else
    {   return first { not $_->label($label) }
           (defined $msgs ? @$msgs : $self->messages);
    }
}

#-------------------------------------------

=section Sub-folders

=ci_method listSubFolders %options
List the names of all sub-folders to this folder, not recursively
decending.  Use these names as argument to M<openSubFolder()>, to get
access to that folder.

For MBOX folders, sub-folders are simulated.

=option  folder FOLDERNAME
=default folder <from calling object>
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

=method openRelatedFolder %options
Open a folder (usually a sub-folder) with the same options as this one.
If there is a folder manager in use, it will be informed about this new
folder.  %options overrule the options which where used for the folder
this method is called upon.
=cut

sub openRelatedFolder(@)
{   my $self    = shift;
    my @options = (%{$self->{MB_init_options}}, @_);

    $self->{MB_manager}
    ? $self->{MB_manager}->open(type => ref($self), @options)
    : (ref $self)->new(@options);
}

=method openSubFolder $subname, %options
Open (or create, if it does not exist yet) a new subfolder in an
existing folder.

=examples
 my $folder = Mail::Box::Mbox->new(folder => '=Inbox');
 my $sub    = $folder->openSubFolder('read');

=cut

sub openSubFolder($@)
{   my $self = shift;
    my $name = $self->nameOfSubFolder(shift);
    $self->openRelatedFolder(@_, folder => $name);
}

=ci_method nameOfSubFolder $subname, [$parentname]
Returns the constructed name of the folder with NAME, which is a
sub-folder of this current one.  You have either to call this method
as instance method, or specify a $parentname.

=examples how to get the name of a subfolder
 my $sub = Mail::Box::Mbox->nameOfSubfolder('xyz', 'abc');
 print $sub;                        # abc/xyz

 my $f = Mail::Box::Mbox->new(folder => 'abc');
 print $f->nameOfSubfolder('xyz');  # abc/xyz

 my $sub = Mail::Box::Mbox->nameOfSubfolder('xyz', undef);
 print $sub;                        # xyz

=cut

sub nameOfSubFolder($;$)
{   my ($thing, $name) = (shift, shift);
    my $parent = @_ ? shift : ref $thing ? $thing->name : undef;
    defined $parent ? "$parent/$name" : $name;
}

=ci_method topFolderWithMessages
Some folder types can have messages in the top-level folder, some other
can't.
=cut

sub topFolderWithMessages() { 1 }

#-------------------------------------------

=section Internals

=method read %options
Read messages from the folder into memory.  The %options are folder
specific.  Do not call C<read()> yourself: it will be called for you
when you open the folder via the manager or instantiate a folder
object directly.

NOTE: if you are copying messages from one folder to another, use
M<addMessages()> instead of C<read()>.

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

    $self;
}

#-------------------------------------------

=method write %options

Write the data to disk.  The folder (a C<true> value) is returned if
successful.  Deleted messages are transformed into destroyed messages:
their memory is freed.

WARNING: When moving messages from one folder to another, be sure to
write (or M<close()>) the destination folder before writing (or closing)
the source folder: otherwise you may lose data if the system crashes or
if there are software problems.

To write a folder to a different file, you must first create a new folder,
then move all the messages, and then write or M<close()> that new folder.

=option  force BOOLEAN
=default force <false>

Override write-protection with M<new(access)> while opening the folder
(whenever possible, it may still be blocked by the operating system).

=option  save_deleted BOOLEAN
=default save_deleted <false>

Do also write messages which where flagged to be deleted to their folder.  The
flag for deletion is conserved (when possible), which means that a re-open of
the folder may remove the messages for real.  See M<close(save_deleted)>.

=error Folder $name is opened read-only

You can not write to this folder unless you have opened the folder to
write or append with M<new(access)>, or the C<force> option is set true.

=error Writing folder $name failed

For some reason (you probably got more error messages about this problem)
it is impossible to write the folder, although you should because there
were changes made.

=cut

sub write(@)
{   my ($self, %args) = @_;

    unless($args{force} || $self->writable)
    {   $self->log(ERROR => "Folder $self is opened read-only.");
        return;
    }

    my (@keep, @destroy);
    if($args{save_deleted})
    {   @keep = $self->messages;
    }
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

=method determineBodyType $message, $head
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

=method storeMessage $message
Store the message in the folder without the checks as performed by
M<addMessage()>.
=cut

sub storeMessage($)
{   my ($self, $message) = @_;

    push @{$self->{MB_messages}}, $message;
    $message->seqnr( @{$self->{MB_messages}} -1);
    $message;
}

=method lineSeparator [<STRING|'CR'|'LF'|'CRLF'>]
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

=ci_method create $foldername, %options
Create a folder.  If the folder already exists, it will be left unchanged.
The folder is created, but not opened!  If you want to open a file which
may need to be created, then use M<Mail::Box::Manager::open()> with the
create flag, or M<Mail::Box::new(create)>.

=option  folderdir DIRECTORY
=default folderdir undef
When the foldername is preceded by a C<=>, the C<folderdir> directory
will be searched for the named folder.
=cut

sub create($@) {shift->notImplemented}

=c_method foundIn [$foldername], %options
Determine if the specified folder is of the type handled by the
folder class. This method is extended by each folder sub-type.

The $foldername specifies the name of the folder, as is specified by the
application.  You need to specified the C<folder> option when you skip
this first argument.

%options is a list of extra information for the request.  Read
the documentation for each type of folder for type specific options, but
each folder class will at least support the C<folderdir> option:

=option  folderdir DIRECTORY
=default folderdir undef
The location where the folders of this class are stored by default.  If the
user specifies a name starting with a C<=>, that indicates that the folder is
to be found in this default DIRECTORY.

=examples
 Mail::Box::Mbox->foundIn('=markov',
     folderdir => "$ENV{HOME}/Mail");
 Mail::Box::MH->foundIn(folder => '=markov');
=cut

=method coerce $message, %options
Coerce the $message to be of the correct type to be placed in the
folder.  You can specify M<Mail::Internet> and M<MIME::Entity> objects
here: they will be translated into Mail::Message messages first.
=cut

sub coerce($@)
{   my ($self, $message) = (shift, shift);
    my $mmtype = $self->{MB_message_type};
    $message->isa($mmtype) ? $message : $mmtype->coerce($message, @_);
}

=method readMessages %options
Called by M<read()> to actually read the messages from one specific
folder type.  The M<read()> organizes the general activities.

The %options are C<trusted>, C<head_type>, C<field_type>,
C<message_type>, C<body_delayed_type>, and C<head_delayed_type> as
defined by the folder at hand.  The defaults are the constructor
defaults (see M<new()>).
=cut

sub readMessages(@) {shift->notImplemented}

=method updateMessages %options
Called by M<update()> to read messages which arrived in the folder
after it was opened.  Sometimes, external applications dump messages
in a folder without locking (or using a different lock than your
application does).

Although this is quite a dangerous, it only fails when a folder is
updated (reordered or message removed) at exactly the same time as
new messages arrive.  These collisions are sparse.

The options are the same as for M<readMessages()>.
=cut

sub updateMessages(@) { shift }

=method writeMessages %options
Called by M<write()> to actually write the messages from one specific
folder type.  The C<write> organizes the general activities.  All options
to M<write()> are passed to C<writeMessages> as well.  Besides, a few extra
are added by C<write> itself.

=requires messages ARRAY
The messages to be written, which is a sub-set of all messages in the
current folder.
=cut

sub writeMessages(@) {shift->notImplemented}

=method locker
Returns the locking object.
=cut

sub locker() { shift->{MB_locker} }

=method toBeThreaded $messages
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

=method toBeUnthreaded $messages
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

=section Other methods

=ci_method timespan2seconds $time
$time is a string, which starts with a float, and then one of the
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
    {   $_[0]->log(ERROR => "Invalid timespan '$_' specified.");
        undef;
    }
}

#-------------------------------------------

=section Error handling

=section Cleanup

=method DESTROY
This method is called by Perl when an folder-object is no longer accessible
by the rest of the program.
=cut

sub DESTROY
{   my $self = shift;
    $self->close unless in_global_destruction || $self->{MB_is_closed};
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

=chapter DETAILS

=section Different kinds of folders

In general, there are three classes of folders: those who group messages
per file, those who group messages in a directory, and those do not
provide direct access to the message data.  These folder types are
each based on a different base class.

=over 4

=item * File based folders M<Mail::Box::File>

File based folders maintain a folder (a set of messages) in one
single file.  The advantage is that your folder has only one
single file to access, which speeds-up things when all messages
must be accessed at once.

One of the main disadvantages over directory based folders
is that you have to construct some means to keep all message apart.
For instance MBOX adds a message separator line between the messages
in the file, and this line can cause confusion with the message's
contents.

Where access to all messages at once is faster in file based folders,
access to a single message is (much) slower, because the whole folder
must be read.  However, in directory based folders you have to figure-out
which message you need, which may be a hassle as well.

Examples of file based folders are MBOX, DBX, and NetScape.

=item * Directory based folders M<Mail::Box::Dir>

In stead of collecting multiple messages in one file, you can also
put each message in a separate file and collect those files in a
directory to represent a folder.

The main disadvantages of these folders are the enormous amount of
tiny files you usually get in your file-system.  It is extremely
slow to search through your whole folder, because many files have
to be opened to do so.

The best feature of this organization is that each message is kept
exactly as it was received, and can be processed with external scripts
as well: you do not need any mail user agent (MUA).

Examples of directoy organized folders are MH, Maildir, EMH, and XMH.

=item * Network (external) folders M<Mail::Box::Net>

Where both types described before provide direct access to the
message data, maintain these folder types the message data for you:
you have to request for messages or parts of them.  These folders
do not have a filename, file-system privileges and system locking
to worry about, but typically require a hostname, folder and message
IDs, and authorization.

Examples of these folder types are the popular POP and IMAP, and
database oriented message storage.

=back

=section Available folder types

=over 4

=item * M<Mail::Box::Dbx> (read only)
Dbx files are created by Outlook Express. Using the external (optional)
M<Mail::Transport::Dbx> module, you can read these folders, even
when you are running MailBox on a UNIX/Linux platform.

Writing and deleting messages is not supported by the library, and
therefore not by MailBox. Read access is enough to do folder conversions,
for instance.

=item * M<Mail::Box::IMAP4> (partially)
The IMAP protocol is very complex.  Some parts are implemented to
create (sub-optimal but usable) IMAP clients.  Besides, there are
also some parts for IMAP servers present.  The most important lacking
feature is support for encrypted connections.

=item * M<Mail::Box::Maildir>
Maildir folders have a directory for each folder.  A folder directory
contains C<tmp>, C<new>, and C<cur> sub-directories, each containting
messages with a different purpose.  Files with new messages are created
in C<tmp>, then moved to C<new> (ready to be accepted).  Later, they are
moved to the C<cur> directory (accepted).  Each message is one file with
a name starting with timestamp.  The name also contains flags about the
status of the message.

Maildir folders can not be used on Windows by reason of file-name
limitations on that platform.

=item * M<Mail::Box::Mbox>
A folder type in which all related messages are stored in one file.  This
is a very common folder type for UNIX.

=item * M<Mail::Box::MH>
This folder creates a directory for each folder, and a message is one
file inside that directory.  The message files are numbered sequentially
on order of arrival.  A special C<.mh_sequences> file maintains flags
about the messages.

=item * M<Mail::Box::POP3> (read/delete only)
POP3 is a protocol which can be used to retrieve messages from a
remote system.  After the connection to a POP server is made, the
messages can be looked at and removed as if they are on the local
system.

=item * M<Mail::Box::Netzwert>
The Netzwert folder type is optimized for mailbox handling on a cluster
of systems with a shared NFS storage.  The code is not released under
GPL (yet)

=back

Other folder types are on the (long) wishlist to get implemented.  Please,
help implementing more of them.

=section Folder class implementation

The class structure of folders is very close to that of messages.  For
instance, a M<Mail::Box::File::Message> relates to a M<Mail::Box::File>
folder.  The folder types are:

                    M<Mail::Box::Netzwert>
 M<Mail::Box::Mbox>   | M<Mail::Box::Maildir> M<Mail::Box::POP3>
 |  M<Mail::Box::Dbx> | | M<Mail::Box::MH>    |  M<Mail::Box::IMAP4>
 |  |               | | |                 |  |
 |  |               | | |                 |  |
 M<Mail::Box::File>   M<Mail::Box::Dir>       M<Mail::Box::Net>
       |                  |                   |
       `--------------.   |   .---------------'
                      |   |   |
                      M<Mail::Box>
                          |
                          |
                    M<Mail::Reporter> (general base class)

By far most folder features are implemented in M<Mail::Box>, so
available to all folder types.  Sometimes, features which appear
in only some of the folder types are simulated for folders that miss
them, like sub-folder support for MBOX.
=cut

1;
