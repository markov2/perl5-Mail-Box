use strict;
use warnings;

package Mail::Message;
use base 'Mail::Reporter';

use Mail::Message::Part;
use Mail::Message::Head::Complete;
use Mail::Message::Construct;

use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Body::Nested;

use Carp;

=chapter NAME

Mail::Message - general message object

=chapter SYNOPSIS

 use M<Mail::Box::Manager>;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open(folder => 'InBox');
 my $msg    = $folder->message(2);    # $msg is a Mail::Message now

 my $subject = $msg->subject;         # The message's subject
 my @cc      = $msg->cc;              # List of Mail::Address'es

 my $msg       = Mail::Message->build(...);
 my $reply_msg = Mail::Message->reply(...);
 my $frwd_msg  = Mail::Message->forward(...);

 my Mail::Message::Head $head = $msg->head;
 my Mail::Message::Body $body = $msg->decoded;
 $msg->decoded->print($outfile);

=chapter DESCRIPTION

A C<Mail::Message> object is a container for MIME-encoded message information,
as defined by RFC2822.  Everything what is not specificly related to storing
the messages in mailboxes (folders) is implemented in this class.  Methods
which are are related to folders is implemented in the M<Mail::Box::Message>
extension.

The main methods are M<get()>, to get information from a message header
field, and M<decoded()> to get the intended content of a message.
But there are many more which can assist your program.

Complex message handling, like construction of replies and forwards, are
implemented in separate packages which are autoloaded into this class.
This means you can simply use these methods as if they are part of this class.
Those package add functionality to all kinds of message objects.

=chapter METHODS

=section Constructors

=cut

our $crlf_platform;
BEGIN { $crlf_platform = $^O =~ m/win32|cygwin/i }

#------------------------------------------

=c_method new OPTIONS

=option  body OBJECT
=default body undef

Instantiate the message with a body which has been created somewhere
before the message is constructed.  The OBJECT must be a sub-class
of Mail::Message::Body.  See also M<body()> and M<storeBody()>.

=option  body_type CLASS
=default body_type M<Mail::Message::Body::Lines>

Default type of body to be created for M<readBody()>.

=option  head OBJECT
=default head undef

Instantiate the message with a head which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of M<Mail::Message::Head>. See also M<head()>.

=option  field_type CLASS
=default field_type undef

=option  head_type CLASS
=default head_type M<Mail::Message::Head::Complete>

Default type of head to be created for M<readHead()>.

=option  messageId STRING
=default messageId undef

The id on which this message can be recognized.  If none specified and
not defined in the header --but one is needed-- there will be one assigned
to the message to be able to pass unique message-ids between objects.

=option  modified BOOLEAN
=default modified <false>

Flags this message as being modified from the beginning on.  Usually,
modification is auto-detected, but there may be reasons to be extra
explicit.

=option  trusted BOOLEAN
=default trusted <false>

Is this message from a trusted source?  If not, the content must be
checked before use.  This checking will be performed when the
body data is decoded or used for transmission.

=option  labels ARRAY|HASH
=default labels {}

Initial values of the labels.  In case of M<Mail::Box::Message>'s, this
shall reflect the state the message is in.  For newly constructed
M<Mail::Message>'s, this may be anything you want, because M<coerce()>
will take care of the folder specifics once the message is added to one.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    # Field initializations also in coerce()
    $self->{MM_modified}  = $args->{modified}  || 0;
    $self->{MM_trusted}   = $args->{trusted}   || 0;
    $self->{MM_labels}    = {};

    # Set the header

    my $head;
    if(defined($head = $args->{head})) { $self->head($head) }
    elsif(my $msgid = $args->{messageId} || $args->{messageID})
    {   $self->takeMessageId($msgid);
    }

    # Set the body
    if(my $body = $args->{body})
    {   $self->{MM_body} = $body;
        $body->message($self);
    }

    $self->{MM_body_type} = $args->{body_type}
       if defined $args->{body_type};

    $self->{MM_head_type} = $args->{head_type}
       if defined $args->{head_type};

    $self->{MM_field_type} = $args->{field_type}
       if defined $args->{field_type};

    my $labels = $args->{labels} || [];
    $self->{MM_labels} = { ref $labels eq 'ARRAY' ? @$labels : %$labels };

    $self;
}

#------------------------------------------

=c_method coerce MESSAGE

Coerce a MESSAGE into a Mail::Message.  In some
occasions, for instance where you add a message to a folder, this
coercion is automatically called to ensure that the correct message
type is stored.

The coerced message is returned on success, otherwise C<undef>.  The
coerced message may be a reblessed version of the original message
or a new object.  In case the message has to be specialized, for
instance from a general Mail::Message into a Mail::Box::Mbox::Message,
no copy is needed.  However, to coerce a Mail::Internet object into
a Mail::Message, a lot of copying and converting will take place.

Valid MESSAGEs which can be coerced into Mail::Message objects
are of type

=over 4

=item * Any type of M<Mail::Box::Message>

=item * M<MIME::Entity>'s, using M<Mail::Message::Convert::MimeEntity>

=item * M<Mail::Internet>'s, using M<Mail::Message::Convert::MailInternet>

=back

M<Mail::Message::Part>'s, which are extensions of C<Mail::Message>'s,
can also be coerced directly from a M<Mail::Message::Body>.

=examples

 my $folder  = Mail::Box::Mbox->new;
 my $message = Mail::Message->build(...);

 my $coerced = Mail::Box::Mbox::Message->coerce($message);
 $folder->addMessage($coerced);

Simpler replacement for the previous two lines:

 my $coerced = $folder->addMessage($message);

=cut

my $mail_internet_converter;
my $mime_entity_converter;

sub coerce($)
{   my ($class, $message) = @_;

    return bless $message, $class
        if $message->isa(__PACKAGE__);

    if($message->isa('MIME::Entity'))
    {   unless($mime_entity_converter)
        {   eval {require Mail::Message::Convert::MimeEntity};
                confess "Install MIME::Entity" if $@;

            $mime_entity_converter = Mail::Message::Convert::MailInternet->new;
        }

        $message = $mime_entity_converter->from($message)
            or return;
    }

    elsif($message->isa('Mail::Internet'))
    {   unless($mail_internet_converter)
        {   eval {require Mail::Message::Convert::MailInternet};
            confess "Install Mail::Internet" if $@;

            $mail_internet_converter = Mail::Message::Convert::MimeEntity->new;
        }

        $message = $mail_internet_converter->from($message)
            or return;
    }

    else
    {   my $what = ref $message ? 'a'.ref($message).' object' : 'text';
        confess "Cannot coerce $what into a ". __PACKAGE__." object.\n";
    }

    $message->{MM_modified}  ||= 0;

    bless $message, $class;
}

#------------------------------------------

=method clone

Create a copy of this message.  Returned is a C<Mail::Message> object.
The head and body, the log and trace levels are taken.  Labels are
copied with the message, but the delete and modified flags are not.
 
BE WARNED: the clone of any kind of message (or a message part)
will B<always> be a C<Mail::Message> object.  For example, a
M<Mail::Box::Message>'s clone is detached from the folder of its original.
When you use M<Mail::Box::addMessage()> with the cloned message at hand,
then the clone will automatically be coerced into the right message type
to be added.

See also M<Mail::Box::Message::copyTo()> and M<Mail::Box::Message::moveTo()>.

=example

 $copy = $msg->clone;

=cut

sub clone()
{   my $self  = shift;

    # First clone body, which may trigger head load as well.  If head is
    # triggered first, then it may be decided to be lazy on the body at
    # moment.  And then the body would be triggered.

    my $clone = Mail::Message->new
     ( body  => $self->body->clone
     , head  => $self->head->clone
     , $self->logSettings
     );

    my %labels = %{$self->{MM_labels}};
    $clone->{MM_labels} = \%labels;
    $clone;
}

#------------------------------------------

=section Constructing a message

=section The Message

=method messageId

Retrieve the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

sub messageId() { $_[0]->{MM_message_id} || $_[0]->takeMessageId}
sub messageID() {shift->messageId}   # compatibility

#------------------------------------------

=method container

If the message is a part of another message, C<container> returns the
reference to the containing body.

=examples

 my Mail::Message $msg = ...
 return unless $msg->body->isMultipart;
 my $part   = $msg->body->part(2);

 return unless $part->body->isMultipart;
 my $nested = $part->body->part(3);

 $nested->container;  # returns $msg->body
 $nested->toplevel;   # returns $msg
 $msg->container;     # returns undef
 $msg->toplevel;      # returns $msg
 $msg->isPart;        # returns false
 $part->isPart;       # returns true

=cut

sub container() { undef } # overridden by Mail::Message::Part

#------------------------------------------

=method isPart

Returns true if the message is a part of another message.  This is
the case for M<Mail::Message::Part> extensions of C<Mail::Message>.

=cut

sub isPart() { 0 } # overridden by Mail::Message::Part

#------------------------------------------

=method toplevel

Returns a reference to the main message, which will be the current
message if the message is not part of another message.

=cut

sub toplevel() { shift } # overridden by Mail::Message::Part

#------------------------------------------

=method isDummy

Dummy messages are used to fill holes in linked-list and such, where only
a message-id is known, but not the place of the header of body data.

This method is also available for M<Mail::Message::Dummy> objects,
where this will return C<true>.  On any extension of C<Mail::Message>,
this will return C<false>.

=cut

sub isDummy() { 0 }

#------------------------------------------

=method print [FILEHANDLE]

Print the message to the FILE-HANDLE, which defaults to the selected
filehandle, without the encapsulation sometimes required by a folder
type, like M<write()> does.

=examples

 $message->print(\*STDERR);  # to the error output
 $message->print;            # to the selected file

 my $out = IO::File->new('out', 'w');
 $message->print($out);      # no encapsulation: no folder
 $message->write($out);      # with encapsulation: is folder.

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || select;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------

=method write [FILEHANDLE]

Write the message to the FILE-HANDLE, which defaults to the selected
FILEHANDLE, with all surrounding information which is needed to put
it correctly in a folder file.

In most cases, the result of C<write> will be the same as with M<print()>.
The main exception is for Mbox folder messages, which will get printed
with their leading 'From ' line and a trailing blank.  Each line of
their body which starts with 'From ' will have an 'E<gt>' added in front.

=cut

sub write(;$)
{   my $self = shift;
    my $out  = shift || select;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------

=method send [MAILER], OPTIONS

Transmit the message to anything outside this Perl program.  MAILER
is a M<Mail::Transport::Send> object.  When the MAILER is not specified, one
will be created, and kept as default for the next messages as well.

The OPTIONS are mailer specific, and a mixture of what is usable for
the creation of the mailer object and the sending itself.  Therefore, see
for possible options M<Mail::Transport::Send::new()> and
M<Mail::Transport::Send::send()>.

=example

 $message->send;

is short (but little less flexibile) for

 my $mailer = M<Mail::Transport::SMTP>->new(@smtpopts);
 $mailer->send($message, @sendopts);

See examples/send.pl in the distribution of M<Mail::Box>.

=error No default mailer found to send message.

The message M<send()> mechanism had not enough information to automatically
find a mail transfer agent to sent this message.  Specify a mailer
explicitly using the C<via> options.

=cut

my $default_mailer;

sub send(@)
{   my ($self, @options) = @_;

    require Mail::Transport::Send;

    my $mailer
       = ref $_[0] && $_[0]->isa('Mail::Transport::Send') ? shift
       : !@options && defined $default_mailer             ? $default_mailer
       : ($default_mailer = Mail::Transport::Send->new(@options));

    $self->log(ERROR => "No default mailer found to send message."), return
        unless defined $mailer;

    $mailer->send($self, @options);
}

#------------------------------------------

=method size

Returns the size of the whole message in bytes.  This does assume that each
line ending is represented by one character (like UNIX, MacOS, and sometimes
Cygwin), and not two characters (like Windows and sometimes Cygwin).

If you write the message to file on a system which uses CR and LF to end a
single line (all Windows versions), the result in file will be M<nrLines()>
larger than this method returns.

=cut

sub size()
{   my $self = shift;
    $self->head->size + $self->body->size;
}

#------------------------------------------

=section The header

=method head [HEAD]

Return (optionally after setting) the HEAD of this message.
The head must be an (sub-)class of M<Mail::Message::Head>.
When the head is added, status information is taken from it
and transformed into labels.  More labels can be added by the
LABELS hash.  They are added later.

=example

 $msg->head(M<Mail::Message::Head>->new);  # set
 my $head = $msg->head;                 # get

=cut

sub head(;$)
{   my $self = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    unless(defined $head)
    {   delete $self->{MM_head};
        return undef;
    }

    $self->log(INTERNAL => "wrong type of head for $self")
        unless ref $head && $head->isa('Mail::Message::Head');

    $head->message($self);

    if(my $old = $self->{MM_head})
    {   $self->{MM_modified}++ unless $old->isDelayed;
    }

    $self->{MM_head} = $head;

    $self->takeMessageId unless $head->isDelayed;

    $head;
}

#------------------------------------------

=method get FIELDNAME

Returns the value which is stored in the header field with the specified
name.  The FIELDNAME is case insensitive.  The I<unfolded body> of the
field is returned, stripped from any attributes.
See M<Mail::Message::Field::body()>.

If the field has multiple appearances in the header, only the last
instance is returned.  If you need more complex handing of fields, then
call M<Mail::Message::Head::get()> yourself.  See M<study()> when you
want to be smart, doing the better (but slower) job.

=example the get() short-cut for header fields

 print $msg->get('Content-Type'), "\n";

Is equivalent to:

 print $msg->head->get('Content-Type')->body, "\n";

=cut

sub get($)
{   my $field = shift->head->get(shift) || return undef;
    $field->body;
}

#------------------------------------------

=method study FIELDNAME

Study the content of a field, like M<get()> does, with as main difference
that a M<Mail::Message::Field::Full> object is returned.  These objects
stringify to an utf8 decoded representation of the data contained in
the field, where M<get()> does not decode.
See M<Mail::Message::Field::study()>.

=example the study() short-cut for header fields

 print $msg->study('to'), "\n";

Is equivalent to:

 print $msg->head->study('to'), "\n";       # and
 print $msg->head->get('to')->study, "\n";

=cut

sub study($)
{  my $head = shift->head or return;
   scalar $head->study(@_);    # return only last
}

#-------------------------------------------

=method from

Returns the address of the sender.  It is possible to have more than
one address specified in the C<From> field of the message. Therefore a
list of M<Mail::Address> objects is returned, which usually has
length 1.

If you need one address of a sender, for instance to create a reply to,
then use M<sender()>.

=example using from() to get all sender addresses

 my @from = $message->from;

=cut

sub from() { map {$_->addresses} shift->head->get('From') }

#-------------------------------------------

=method sender

Returns exactly one address, which is the originator of this message.
The returned M<Mail::Address> object is taken from the C<Sender> header
field, unless that field does not exists, in which case the first
address from the C<From> field is taken.  If none of both provide
an address, C<undef> is returned.

=example using sender() to get exactly one sender address

 my $sender = $message->sender;
 print "Reply to: ", $sender->format, "\n" if defined $sender;

=cut

sub sender()
{   my $self   = shift;
    my $sender = $self->head->get('Sender') || $self->head->get('From')
               || return ();

    ($sender->addresses)[0];                 # first specified address
}

#-------------------------------------------

=method to

Returns the addresses which are specified on the C<To> header line (or lines).
A list of M<Mail::Address> objects is returned.  The people addressed
here are the targets of the content, and should read it contents
carefully.

=examples using to() to get all primar destination addresses

 my @to = $message->to;

=cut

sub to() { map {$_->addresses} shift->head->get('To') }

#-------------------------------------------

=method cc

Returns the addresses which are specified on the C<Cc> header line (or lines)
A list of M<Mail::Address> objects is returned.  C<Cc> stands for
I<Carbon Copy>; the people addressed on this line receive the message
informational, and are usually not expected to reply on its content.

=cut

sub cc() { map {$_->addresses} shift->head->get('Cc') }

#-------------------------------------------

=method bcc

Returns the addresses which are specified on the C<Bcc> header line (or lines)
A list of M<Mail::Address> objects is returned.
C<Bcc> stands for I<Blind Carbon Copy>: destinations of the message which are
not listed in the messages actually sent.  So, this field will be empty
for received messages, but may be present in messages you construct yourself.

=cut

sub bcc() { map {$_->addresses} shift->head->get('Bcc') }

#-------------------------------------------

=method date

Returns the last C<Date> header line as string.

=example using date() to get the C<Date> header field

 my $date = $message->date;

=cut

sub date() { shift->head->get('Date') }

#-------------------------------------------

=method destinations

Returns a list of M<Mail::Address> objects which contains the combined
info of active C<To>, C<Cc>, and C<Bcc> addresses.  Double addresses are
removed if detectable.

=cut

sub destinations()
{   my $self = shift;
    my %to = map { (lc($_->address) => $_) }
                  $self->to, $self->cc, $self->bcc;
    values %to;
}

#-------------------------------------------

=method subject

Returns the message's subject, or the empty string.

=example using subject() to get the message's subject

 print $msg->subject;

=cut

sub subject()
{   my $subject = shift->get('subject');
    defined $subject ? $subject : '';
}

#-------------------------------------------

=method guessTimestamp

Return an estimate on the time this message was sent.  The data is
derived from the header, where it can be derived from the C<date> and
C<received> lines.  For MBox-like folders you may get the date from
the from-line as well.

This method may return C<undef> if the header is not parsed or only
partially known.  If you require a time, then use the timestamp()
method, described below.

=example using guessTimestamp() to get a transmission date

 print "Receipt ", ($message->timestamp || 'unknown'), "\n";

=cut

sub guessTimestamp() {shift->head->guessTimestamp}

#-------------------------------------------

=method timestamp

Get a timestamp, doesn't matter how much work it is.  If it is impossible
to get a time from the header-lines, the current time-of-living is taken.

=cut

sub timestamp() {shift->head->timestamp}

#------------------------------------------

=method nrLines

Returns the number of lines used for the whole message.

=cut

sub nrLines()
{   my $self = shift;
    $self->head->nrLines + $self->body->nrLines;
}

#-------------------------------------------

=section The body

=method body [BODY]

Return the body of this message.  BE WARNED that this returns
you an object which may be encoded: use decoded() to get a body
with usable data.

With options, a new BODY is set for this message.  This is B<not>
for normal use unless you understand the consequences: you change
the message content without changing the message-ID.  The right
way to go is via

 $message = M<Mail::Message>->buildFromBody($body);  # or
 $message = M<Mail::Message>->build($body);          # or
 $message = $origmsg->forward(body => $body);

The BODY must be an (sub-)class of M<Mail::Message::Body>.  In this case,
information from the specified body will be copied into the header.  The
body object will be encoded if needed, because messages written to file
or transmitted shall not contain binary data.  The converted body
is returned.

When BODY is C<undef>, the current message body will be dissected from
the message.  All relation will be cut.  The body is returned, and
can be connected to a different message.

=examples

 my $body      = $msg->body;
 my @encoded   = $msg->body->lines;

 my $new       = M<Mail::Message::Body>->new(mime_type => 'text/html');
 my $converted = $msg->body($new);

=cut
  
sub body(;$@)
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my $head = $self->head;
    $head->removeContentInfo if defined $head;

    my ($rawbody, %args) = @_;
    unless(defined $rawbody)
    {   # Disconnect body from message.
        my $body = delete $self->{MM_body};
        $body->message(undef) if defined $body;
        return $body;
    }

    $self->log(INTERNAL => "wrong type of body for $rawbody")
        unless ref $rawbody && $rawbody->isa('Mail::Message::Body');

    # Bodies of real messages must be encoded for safe transmission.
    # Message parts will get encoded on the moment the whole multipart
    # is transformed into a real message.
    my $body = $self->isPart ? $rawbody : $rawbody->encoded;
    $body->contentInfoTo($self->head);

    my $oldbody = $self->{MM_body};
    return $body if defined $oldbody && $body==$oldbody;

    $body->message($self);
    $body->modified(1) if defined $oldbody;

    $self->{MM_body} = $body;
}

#------------------------------------------

=method decoded OPTIONS

Decodes the body of this message, and returns it as a body object.  If there
was no encoding, the body object as read from file is passed on, however,
some more work will be needed when a serious encoding is encountered.
The OPTIONS control how the conversion takes place.

=option  keep BOOLEAN
=default keep <false>

Controls whether the decoded result will be kept.  If not, the decoding
may be performed more than once.  However, it will consume extra
resources...

=option  result_type BODYTYPE
=default result_type <type of body>

Specifies which kind of body should be used for the final result, and
eventual intermediate conversion stages.  It is not sure that this
will be the type of the body returned.  BODYTYPE extends
M<Mail::Message::Body>.

=examples

 $message->decoded->print(\*OUT);
 $message->decoded->print;

 my $dec = $message->body($message->decoded);
 my $dec = $message->decoded(keep => 1);   # same

=cut

sub decoded(@)
{   my ($self, %args) = @_;

    return $self->{MB_decoded} if $self->{MB_decoded};

    my $body    = $self->body->load or return;
    my $decoded = $body->decoded(result_type => $args{result_type});

    $self->{MB_decoded} = $decoded if $args{keep};
    $decoded;
}

#------------------------------------------

=method encode OPTIONS

Encode the message to a certain format.  Read the details in the
dedicated manual page M<Mail::Message::Body::Encode>.  The OPTIONS which
can be specified here are those of the M<Mail::Message::Body::encode()>
method.  

=cut

sub encode(@)
{   my $body = shift->body->load;
    $body ? $body->encode(@_) : undef;
}

#-------------------------------------------

=method isMultipart

Check whether this message is a multipart message (has attachments).  To
find this out, we need at least the header of the message; there is no
need to read the body of the message to detect this.

=cut

sub isMultipart() {shift->head->isMultipart}

#-------------------------------------------

=method isNested

Returns C<true> for C<message/rfc822> messages and message parts.

=cut

sub isNested() {shift->body->isNested}

#-------------------------------------------

=method parts ['ALL'|'ACTIVE'|'DELETED'|'RECURSE'|FILTER]

Returns the I<parts> of this message. Usually, the term I<part> is used
with I<multipart> messages: messages which are encapsulated in the body
of a message.  To abstract this concept: this method will return you
all header-body combinations which are stored within this message.
Objects returned are C<Mail::Message>'s and M<Mail::Message::Part>'s.

The option default to 'ALL', which will return the message itself for
single-parts, the nested content of a message/rfc822 object, respectively
the parts of a multipart without recursion.  In case of 'RECURSE', the
parts of multiparts will be collected recursively.  This option cannot
be combined with the other options, which you may want: it that case
you have to test yourself.

'ACTIVE' and 'DELETED' check for the deleted flag on messages and
message parts.  The FILTER is a code reference, which is called for
each part of the messagei; each part as C<RECURSE> would return.

=examples

 my @parts = $msg->parts;           # $msg not multipart: returns ($msg)
 my $parts = $msg->parts('ACTIVE'); # returns ($msg)

 $msg->delete;
 my @parts = $msg->parts;           # returns ($msg)
 my $parts = $msg->parts('ACTIVE'); # returns ()

=cut

sub parts(;$)
{   my $self    = shift;
    my $what    = shift || 'ACTIVE';

    my $body    = $self->body;
    my $recurse = $what eq 'RECURSE' || ref $what;

    my @parts
     = $body->isNested     ? $body->nested->parts($what)
     : $body->isMultipart  ? $body->parts($recurse ? 'RECURSE' : ())
     :                       $self;

      ref $what eq 'CODE' ? (grep {$what->($_)} @parts)
    : $what eq 'ACTIVE'   ? (grep {not $_->isDeleted } @parts)
    : $what eq 'DELETED'  ? (grep { $_->isDeleted } @parts)
    : $what eq 'ALL'      ? @parts
    : $recurse            ? @parts
    : confess "Select parts via $what?";
}

#------------------------------------------

=section Flags

=method modified [BOOLEAN]

Returns (optionally after setting) whether this message is flagged as
being modified.  See isModified().

=cut

sub modified(;$)
{   my $self = shift;

    return $self->isModified unless @_;  # compatibility 2.036

    my $flag = shift;
    $self->{MM_modified} = $flag;
    my $head = $self->head;
    $head->modified($flag) if $head;
    my $body = $self->body;
    $body->modified($flag) if $body;

    $flag;
}

#------------------------------------------

=method isModified

Returns whether this message is flagged as being modified.  Modifications
are changes in header lines, when a new body is set to the message
(dangerous), or when labels change.

=cut

sub isModified()
{   my $self = shift;
    return 1 if $self->{MM_modified};

    my $head = $self->head;
    if($head && $head->isModified)
    {   $self->{MM_modified}++;
        return 1;
    }

    my $body = $self->body;
    if($body && $body->isModified)
    {   $self->{MM_modified}++;
        return 1;
    }

    0;
}

#------------------------------------------

=method label LABEL [,VALUE [LABEL, VALUE] ]

Return the value of the LABEL, optionally after setting it to VALUE.  If
the VALUE is C<undef> then the label is removed.  You may specify a list
of LABEL-VALUE pairs at once.  In the latter case, the first VALUE is returned.

Labels are used to store knowledge about handling of the message within
the folder.  Flags about whether a message was read, replied to, or
(in some cases) scheduled for deletion.

Some labels are taken from the header's C<Status> and C<X-Status> lines,
however folder types like MH define a separate label file.

=examples

 print $message->label('seen');
 if($message->label('seen')) {...};
 $message->label(seen => 1);

=cut

sub label($;$)
{   my $self   = shift;
    return $self->{MM_labels}{$_[0]} unless @_ > 1;
    my $return = $_[1];

    my %labels = @_;
    @{$self->{MM_labels}}{keys %labels} = values %labels;
    $return;
}

#------------------------------------------

=method labels

Returns all known labels.  In SCALAR context, it returns the knowledge
as reference to a hash.  This is a reference to the original data, but
you shall *not* change that data directly: call C<label> for
changes!

In LIST context, you get a list of names which are defined.  Be warned
that they will not all evaluate to true, although most of them will.

=cut

sub labels()
{   my $self = shift;
    wantarray ? keys %{$self->{MM_labels}} : $self->{MM_labels};
}

#------------------------------------------

=method isDeleted

A plain C<Mail::Message> is never deleted, but messages in folders and
message parts (both extensions of this message base class) can be.  For
simplicity, this method will always return C<false>: no we are not
deleted.

=cut

# needed for parts('ACTIVE'|'DELETED') on non-folder messages.
sub isDeleted() {0}

#-------------------------------------------

=method labelsToStatus

When the labels were changed, that may effect the C<Status> and/or
C<X-Status> header lines of mbox messages.  Read about the relation
between these fields and the labels in the DETAILS chapter.

The method will carefully only affect the result of M<modified()> when
there is a real change of flags, so not for each call to M<label()>.

=cut

sub labelsToStatus()
{   my $self    = shift;
    my $head    = $self->head;
    my $labels  = $self->labels;

    my $status  = $head->get('status') || '';
    my $newstatus
      = $labels->{seen}    ? 'RO'
      : $labels->{old}     ? 'O'
      : '';

    $head->set(Status => $newstatus)
        if $newstatus ne $status;

    my $xstatus = $head->get('x-status') || '';
    my $newxstatus
      = ($labels->{replied} ? 'A' : '')
      . ($labels->{flagged} ? 'F' : '');

    $head->set('X-Status' => $newxstatus)
        if $newxstatus ne $xstatus;

    $self;
}

#-------------------------------------------

=method statusToLabels

Update the labels according the status lines in the header.  See the
description in the DETAILS chapter.

=cut

sub statusToLabels()
{   my $self    = shift;
    my $head    = $self->head;

    if(my $status  = $head->get('status'))
    {   $self->{MM_labels}{seen} = ($status  =~ /R/ ? 1 : 0);
        $self->{MM_labels}{old}  = ($status  =~ /O/ ? 1 : 0);
    }

    if(my $xstatus = $head->get('x-status'))
    {   $self->{MM_labels}{replied} = ($xstatus  =~ /A/ ? 1 : 0);
        $self->{MM_labels}{flagged} = ($xstatus  =~ /F/ ? 1 : 0);
    }

    $self;
}

#------------------------------------------

=section The whole message as text

=section Internals

=cut

#------------------------------------------
# All next routines try to create compatibility with release < 2.0
sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#------------------------------------------

=method readFromParser PARSER, [BODYTYPE]

Read one message from file.  The PARSER is opened on the file.  First
readHeader() is called, and the head is stored in the message.  Then
readBody() is called, to produce a body.  Also the body is added to
the message without decodings being done.

The optional BODYTYPE may be a body class or a reference to a code
which returns a body-class based on the header.

=cut

sub readFromParser($;$)
{   my ($self, $parser, $bodytype) = @_;

    my $head = $self->readHead($parser)
            || Mail::Message::Head::Complete->new
                 ( message     => $self
                 , field_type  => $self->{MM_field_type}
                 , $self->logSettings
                 );

    my $body = $self->readBody($parser, $head, $bodytype)
       or return;

    $self->head($head);
    $self->storeBody($body);
    $self;
}

#------------------------------------------

=method readHead PARSER [,CLASS]

Read a head into an object of the specified CLASS.  The CLASS defaults to
the C<head_type> option specified at creation of the message (see new()).
The PARSER is the access to the folder's file.

=cut

sub readHead($;$)
{   my ($self, $parser) = (shift, shift);

    my $headtype = shift
      || $self->{MM_head_type} || 'Mail::Message::Head::Complete';

    $headtype->new
      ( message     => $self
      , field_type  => $self->{MM_field_type}
      , $self->logSettings
      )->read($parser);
}

#------------------------------------------

=method readBody PARSER, HEAD [, BODYTYPE]

Read a body of a message.  The PARSER is the access to the folder's
file, and the HEAD is already read.  Information from the HEAD is used
to create expectations about the message's length, but also to determine
the mime-type and encodings of the body data.

The BODYTYPE determines which kind of body will be made and defaults to
the value specified by new(body_type).
BODYTYPE may be the name of a body class, or a reference
to a routine which returns the body's class when passed the HEAD as only
argument.

=cut

my $mpbody = 'Mail::Message::Body::Multipart';
my $nbody  = 'Mail::Message::Body::Nested';
my $lbody  = 'Mail::Message::Body::Lines';

sub readBody($$;$$)
{   my ($self, $parser, $head, $getbodytype) = @_;

    my $bodytype
      = ! $getbodytype   ? ($self->{MM_body_type} || $lbody)
      : ref $getbodytype ? $getbodytype->($self, $head)
      :                    $getbodytype;

    my $body;
    if($bodytype->isDelayed)
    {   $body = $bodytype->new
          ( message           => $self
          , $self->logSettings
          );
    }
    else
    {   my $ct   = $head->get('Content-Type');
        my $type = defined $ct ? lc($ct->body) : 'text/plain';

        # Be sure you have acceptable bodies for multiparts and nested.
        if(substr($type, 0, 10) eq 'multipart/' && !$bodytype->isMultipart)
        {   $bodytype = $mpbody }
        elsif($type eq 'message/rfc822' && !$bodytype->isNested)
        {   $bodytype = $nbody  }

        $body = $bodytype->new
        ( message           => $self
        , checked           => $self->{MM_trusted}
        , $self->logSettings
        );
        $body->contentInfoFrom($head);
    }

    my $lines   = $head->get('Lines');
    my $size    = $head->guessBodySize;

    $body->read
      ( $parser, $head, $getbodytype,
      , $size, (defined $lines ? int $lines->body : undef)
      ) or return;
}

#------------------------------------------

=method storeBody BODY

Where the M<body()> method can be used to set and get a body, with all
the necessary checks, this method is bluntly adding the specified body
to the message.  No conversions, not checking.

=cut

sub storeBody($)
{   my ($self, $body) = @_;
    $self->{MM_body} = $body;
    $body->message($self);
    $body;
}

#-------------------------------------------

=method isDelayed

Check whether the message is delayed (not yet read from file).  Returns
true or false, dependent on the body type.

=cut

sub isDelayed()
{    my $body = shift->body;
     !$body || $body->isDelayed;
}

#------------------------------------------

=method takeMessageId [STRING]

Take the message-id from the STRING, or create one when the C<undef>
is specified.  If not STRING nor C<undef> is given, the current header
of the message is requested for the value of the C<'Message-ID'> field.

Angles (if present) are removed from the id. 

=cut

sub takeMessageId(;$)
{   my $self  = shift;
    my $msgid = (@_ ? shift : $self->get('Message-ID')) || '';

    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }
 
    $msgid = $self->head->createMessageId
        unless length $msgid;

    $self->{MM_message_id} = $msgid;
}

#------------------------------------------

=section Error handling

=ci_method shortSize [VALUE]

Represent an integer VALUE representing the size of file or memory,
(which can be large) into a short string using M and K (Megabytes
and Kilobytes).  Without VALUE, the size of the message head is used.

=cut

sub shortSize(;$)
{   my $self = shift;
    my $size = shift;
    $size = $self->head->guessBodySize unless defined $size;

      !defined $size     ? '?'
    : $size < 1_000      ? sprintf "%3d "  , $size
    : $size < 10_000     ? sprintf "%3.1fK", $size/1024
    : $size < 1_000_000  ? sprintf "%3.0fK", $size/1024
    : $size < 10_000_000 ? sprintf "%3.1fM", $size/(1024*1024)
    :                      sprintf "%3.0fM", $size/(1024*1024);
}

#------------------------------------------

=method shortString

Convert the message header to a short string, representing the most
important facts (for debugging purposes only).

=cut

sub shortString()
{   my $self    = shift;
    my $subject = $self->head->get('subject') || '';
    chomp $subject;

    sprintf "%4s(%2d) %-30.30s", $self->shortSize, $subject;
}

#------------------------------------------

=section Cleanup

=method DESTROY

When a message is to accessible anymore by any user's reference, Perl
will call DESTROY for final clean-up.  In this case, the head and
body are released, and de-registered for the folder.  You shall not call
this yourself!

=cut

sub DESTROY()
{   my $self = shift;
    return if $self->inGlobalDestruction;

    $self->SUPER::DESTROY;
    $self->head(undef);
    $self->body(undef);
}

#------------------------------------------

=method destruct

Remove the information contained in the message object.  This will be
ignored when more than one reference to the same message object exists,
because the method has the same effect as assigning C<undef> to the
variable which contains the reference.  Normal garbage collection will
call M<DESTROY()> when possible.

This method is only provided to hide differences with messages which are
located in folders: their M<Mail::Box::Message::destruct()> works quite
differently.

=example of Mail::Message destruct

 my $msg = M<Mail::Message>->read;
 $msg->destruct;
 $msg = undef;    # same

=cut

sub destruct() { $_[0] = undef }

#------------------------------------------

=chapter DETAILS

=section Structure of a Message

A MIME-compliant message is build upon two parts: the I<header> and the
I<body>.

=subsection The header

The header is a list of fields, some spanning more than one line
(I<folded>) each telling something about the message. Information stored
in here are for instance the sender of the message, the receivers of
the message, when it was transported, how it was transported, etc etc.
Headers can grow quite large.

In MailBox, each message object manages exactly one header object
(a M<Mail::Message::Head>) and one body object (a M<Mail::Message::Body>).
The header contains a list of header fields, which are represented by
M<Mail::Message::Field> objects.

=subsection The body

The body contains the "payload": the data to be transfered.
The data can be encoded, only accessible with a specific application,
and may use some weird character-set, like Vietnamese; the MailBox
distribution tries to assist you with handling these e-mails without
the need to know all the details.  This additional information
("meta-information") about the body data is stored in the header.
The header contains more information, for instance about the message
transport and relations to other messages.

=section Message object implementation

The general idea about the structure of a message is

 M<Mail::Message>
  |  |
  |  `-has-one--M<Mail::Message::Body>
  |
  `----has-one--M<Mail::Message::Head>
                  |
                  `-has-many--M<Mail::Message::Field>

However: there are about 7 kinds of body objects, 3 kinds of headers and
3 kinds of fields.  You will usually not see too much of these kinds,
because they are merely created for performance reasons and can be used
all the same, with the exception of the multipart bodies.

A multipart body is either a M<Mail::Message::Body::Multipart>
(mime type C<multipart/*>) or a M<Mail::Message::Body::Nested>
(mime type C<message/rfc822>).  These bodies are more complex:

 M<Mail::Message::Body::Multipart>
  |
  `-has-many--M<Mail::Message::Part>
               |  |
               |  `-has-one--M<Mail::Message::Body>
               |
               `----has-one--M<Mail::Message::Head>

Before you try to reconstruct multiparts or nested messages yourself,
you can better take a look at M<Mail::Message::Construct::Rebuild>.

=section Message class implementation

The class structure of messages is very close to that of folders.  For
instance, a M<Mail::Box::File::Message> relates to a M<Mail::Box::File>
folder.

As extra level of inheritance, it has a M<Mail::Message>, which
is a message without location.  And there is a special case of
message: M<Mail::Message::Part> is a message encapsulated in a
multipart body.

The message types are:

 M<Mail::Box::Mbox::Message>            M<Mail::Box::POP3::Message>
 |  M<Mail::Box::Dbx::Message>      M<Mail::Box::IMAP4::Message>  |
 |  |                                                    |  |
 M<Mail::Box::File::Message>             M<Mail::Box::Net::Message>
         |                                      |
         |       M<Mail::Box::Maildir::Message>    |
         |       |   M<Mail::Box::MH::Message>     |
         |       |   |                          |
         |       M<Mail::Box::Dir::Message>        |
         |                |                     |
         `------------.   |   .-----------------'
                      |   |   |
                   M<Mail::Box::Message>    M<Mail::Message::Part>
                          |                     |
                          |       .-------------'
                          |       |
                      M<Mail::Message>
                          |
                          |
                    M<Mail::Reporter> (general base class)

By far most folder features are implemented in M<Mail::Box>, so
available to all folder types.  Sometimes, features which appear
in only some of the folder types are simulated for folders that miss
them, like sub-folder support for MBOX.

Two strange other message types are defined:
the M<Mail::Message::Dummy>, which fills holes in
M<Mail::Box::Thread::Node> lists, and a M<Mail::Box::Message::Destructed>,
this is an on purpose demolished message to reduce memory consumption.

=section Labels

Labels (also named "Flags") are used to indicate some special condition on
the message, primary targeted on organizational issues: which messages are
already read or should be deleted.  There is a very strong user relation
to labels.

The main complication is that each folder type has its own way of storing
labels.  To give an indication: MBOX folders use C<Status> and C<X-Status>
header fields, MH uses a C<.mh-sequences> file, MAILDIR encodes the flags
in the message's filename, and IMAP has flags as part of the protocol.

Besides, some folder types can store labels with user defined names,
where other lack that feature.  Read all about the specifics in the
manual page of the message type you actually have.

=subsection Predefined labels

To standardize the folder types, MailBox has defined the following labels,
which can be used with the M<label()> and M<labels()> methods on all kinds
of messages:

=over 4

=item * deleted

This message is flagged to be deleted once the folder closes.  Be very
careful about the concept of 'delete' in a folder context (yes, also the
M<Mail::Box::Message::delete()> and M<Mail::Box::Message::deleted()>
methods): it is only a flag, and does not involve immediate action!
This means, for instance, that the memory which is used by Perl to
store the message is not released immediately (see M<destruct()> if you
need to).

=item * draft

The user has prepared this message, but is has not been send (yet).  This
flag is not automatically added to a message by MailBox, and has only
a meaning in user applications.

=item * flagged

Messages can be I<flagged> for some purpose, for instance as result of
a search for spam in a folder.  The M<Mail::Box::messages()> method
can be used to collect all these flagged messages from the folder.

Probably it is more useful to use an understandable name (like C<spam>)
for these selections, however these self-defined labels can not stored
in all folder types.

=item * old

The message was already in the folder when it was opened the last time,
so was not recently added to the folder.  This flag will never automatically
be set by MailBox, because it would probably conflict with the user's
idea of what is old.

=item * replied

The user (or application) has sent a message back to the sender of
the message, as response of this one.  This flag is automatically
set if you use M<reply()>, but not with M<forward()> or M<bounce()>.

=item * seen

When this flag is set, the receiver of the message has consumed the message.
A mail user agent (MUA) will set this flag when the user has opened the
message once.

=back

=subsection Status and X-Status fields

Mbox folders have no special means of storing information about messages
(except the message separator line), and therefore have to revert to
adding fields to the message header when something special comes up.
This feature is also enabled for POP3, although whether that works
depends on the POP server.

All applications which can handle mbox folders support the C<Status> and
C<X-Status> field convensions.  The following encoding is used:

 Flag   Field       Label
 R      Status   => seen    (Read)
 O      Status   => old     (not recent)
 A      X-Status => replied (Answered)
 F      X-Status => flagged

There is no special flag for C<deleted>, which most other folders support:
messages flagged to be deleted will never be written to a folder file when
it is closed.

=cut

1;
