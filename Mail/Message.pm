use strict;
use warnings;

package Mail::Message;
use base 'Mail::Reporter';

use Mail::Message::Part;
use Mail::Message::Head::Complete;

use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Body::Nested;

use Carp;
use IO::ScalarArray;

=head1 NAME

Mail::Message - general message object

=head1 SYNOPSIS

 use Mail::Box::Manager;
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

=head1 DESCRIPTION

A Mail::Message object is a container for MIME-encoded message information,
as defined by RFC2822.  Everything what is not specificly related to storing
the messages in mailboxes (folders) is implemented in this class.  Methods
which are are related to folders is implemented in the Mail::Box::Message
extension.

The main methods are get(), to get information from a message header field,
and decoded() to get the intended content of a message.  But there
are many more which can assist your program.

Complex message handling (like construction of replies) are implemented in the
Mail::Message::Construct package which is autoloaded into this class.  This
means you can simply use these methods as if they are part of this class.
That package adds functionality to all kinds of Mail::Message objects.

=head2 Structure of a Message

A MIME-compliant message is build upon two parts: the I<head> and the
I<body>.  The body contains the I<payload>: the data to be transfered.  The
data can be encoded, only accessible with a specific application, and may use
some weird character-set, like Vietnamese; the Mail::Box module tries to
assist you with handling these e-mails without the need to know all the
detauls.  This additional information (I<meta-information>) about the
body data is stored in the header.

The header is a list of fields, some spanning more than one line (I<folded>)
each telling something about the message. Information stored in here are for
instance the sender of the message, the receivers of the message, when it
was transported, how it was transported, etc etc.  Headers can grow quite
large.

=head2 Implementation

In Mail::Box, each message object manages exactly one header object
(a Mail::Message::Head) and one body object (a Mail::Message::Body).
See the methods in Mail::Message::Construct if you want to do complicated
things.

Mail::Box is as lazy as possible.  Whenever you open a folder, it tries
to avoid processing the messages within that folder.  In stead of parsing
(decoding) the messages when the folder is opened, they are parsed the
moment they are used for the first time.  In Mail::Box, this is called
I<delayed loading>.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

our $crlf_platform;
BEGIN { $crlf_platform = $^O =~ m/win32|cygwin/i }

#------------------------------------------

=method new OPTIONS

=option  body OBJECT
=default body undef

Instantiate the message with a body which has been created somewhere
before the message is constructed.  The OBJECT must be a sub-class
of Mail::Message::Body.  See also body() and storeBody().

=option  body_type CLASS
=default body_type 'Mail::Message::Body::Lines'

Default type of body to be created for readBody().

=option  head OBJECT
=default head undef

Instantiate the message with a head which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of Mail::Message::Head. See also head().

=option  field_type CLASS
=default field_type undef

=option  head_type CLASS
=default head_type 'Mail::Message::Head::Complete'

Default type of head to be created for readHead().

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

    $self->labels(@{$args->{labels}}) if $args->{labels};
    $self;
}

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=method coerce MESSAGE

(Class method) Coerce a MESSAGE into a Mail::Message.  In some
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

=item * Any type of Mail::Box::Message

=item * MIME::Entity's, using Mail::Message::Convert::MimeEntity

=item * Mail::Internet's, using Mail::Message::Convert::MailInternet

=back

Mail::Message::Part's, which are extensions of Mail::Message's,
can also be coerced directly from a Mail::Message::Body.

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

=head2 The Message

=cut

#-------------------------------------------

=method messageId

Retrieve the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

sub messageId() { $_[0]->{MM_message_id} || $_[0]->takeMessageId}
sub messageID() {shift->messageId}   # compatibility

#------------------------------------------

=method modified [BOOLEAN]

Returns (optionally after setting) whether this message is flagged as
being modified.  The modification flag is set C<true> when header lines
are changed, the header or body replaced by a new one, or when labels
are modified.

=cut

sub modified(;$)
{   my $self = shift;

    if(@_)
    {   my $flag = shift;
        $self->{MM_modified} = $flag;
        my $head = $self->head;
        $head->modified($flag) if $head;
        my $body = $self->body;
        $body->modified($flag) if $body;
    }

    return 1 if $self->{MM_modified};

    my $head = $self->head;
    if($head && $head->modified)
    {   $self->{MM_modified}++;
        return 1;
    }

    my $body = $self->body;
    if($body && $body->modified)
    {   $self->{MM_modified}++;
        return 1;
    }

    0;
}

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
the case for Mail::Message::Part extensions of Mail::Message.

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

This method is also available for Mail::Message::Dummy objects, where
this will return C<true>.  On any extension of Mail::Message, this will
return C<false>.

=cut

sub isDummy() { 0 }

#------------------------------------------

=method print [FILEHANDLE]

Print the message to the FILE-HANDLE, which defaults to the selected
filehandle.

=examples

 $message->print(\*STDERR);
 $message->print;

 my $out = IO::File->new('out', 'w');
 $message->print($out);

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || select;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------

=method send [MAILER], OPTIONS

Transmit the message to anything outside this Perl program.  MAILER
is a Mail::Transport::Send object.  When the MAILER is not specified, one
will be created, and kept as default for the next messages as well.
The OPTIONS are mailer specific.

 $message->send;

is short (but little less flexibile) for

 my $mailer = Mail::Transport::SMTP->new(@smtpopts);
 $mailer->send($message, @sendopts);

=cut

my $default_mailer;

sub send(@)
{   my $self   = shift;

    require Mail::Transport::Send;

    my $mailer
       = ref $_[0] && $_[0]->isa('Mail::Transport::Send') ? shift
       : defined $default_mailer  ? $default_mailer
       : ($default_mailer = Mail::Transport->new(@_));

    $self->log(ERROR => "No mailer found"), return
        unless defined $mailer;

    $mailer->send($self, @_);
}

#------------------------------------------

=method size

Returns the size of the whole message in bytes.  This does assume that each
line ending is represented by one character (like UNIX, MacOS, and sometimes
Cygwin), and not two characters (like Windows and sometimes Cygwin).

If you write the message to file on a system which uses CR and LF to end a
single line (all Windows versions), the result in file will be nrLines() larger
than this method returns.

=cut

sub size()
{   my $self = shift;
    $self->head->size + $self->body->size;
}

#------------------------------------------

=method clone

Create a copy of this message.  Returned is a Mail::Message object.
The head and body, the log and trace levels are taken.  Labels are
copied with the message, but the delete and modified flags are not.
 
BE WARNED: the clone of any kind of message (or a message part) will B<always
be a Mail::Message> object.  For example, a Mail::Box::Message's clone is
detached from the folder of its original.  When you use Mail::Box::addMessage()
with the cloned message at hand, then the clone will automatically
be coerced into the right message type to be added.

See also copyTo() and moveTo().

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

=head2 The Header

=cut

#------------------------------------------

=method head [HEAD]

Return (optionally after setting) the HEAD of this message.
The head must be an (sub-)class of Mail::Message::Head.
When the head is added, status information is taken from it
and transformed into labels.  More labels can be added by the
LABELS hash.  They are added later.

=example

 my $head = $msg->head(new Mail::Message::Head);

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

=head2 Header Shortcuts

=cut

#------------------------------------------

=method get FIELD

Returns the value which is stored in the header FIELD with the specified
name.  If the field has multiple appearances in the header, only the last
instance is returned.

The field name is case insensitive.  the I<unfolded body> of the field is
returned, see Mail::Message::Field::unfolded_body().  If you need more complex
handing of fields, then call Mail::Message::Head::get() yourself.

=examples

 print $msg->get('Content-Type'), "\n";

Is equivalent to:

 print $msg->head->get('Content-Type')->unfolded_body, "\n";

=cut

sub get($)
{   my $field = shift->head->get(shift) || return undef;
    $field->body;
}

#-------------------------------------------

=method from

Returns the address(es) of the sender(s).  Returned is a list of
Mail::Address objects, which represent the addresses found on
the C<From> header field.  Usually, this is only one address, but
there can be more.

If you need exactly one address to return (for instance to reply
a message to), you should use sender().

=example

 my @from = $message->from;

=cut

sub from() { map {$_->addresses} shift->head->get('From') }

#-------------------------------------------

=method sender

Returns exactly one address, which is the originator of this message.
The returned Mail::Address object is taken from the C<Sender> header
field, unless that field does not exists, in which case the first
address from the C<From> field is taken.  If none of both provide
an address, C<undef> is returned.

=example

 my $sender = $message->sender;
 print "Reply to: ", $sender->format, "\n" if defined $sender;

=cut

sub sender()
{   my $self   = shift;
    my $sender = ($self->head->get('Sender'))[0];

    $sender = ($self->head->get('From'))[0]  # first from line
        unless defined $sender;

    return undef
        unless defined $sender;

    ($sender->addresses)[0];                 # first specified address
}

#-------------------------------------------

=method to

Returns the addresses which are specified on the C<To> header line(s).
A list of Mail::Address objects is returned.  The people addressed
here are the targets of the content, and should read it contents
carefully.

=examples

 my @to = $message->to;

=cut

sub to() { map {$_->addresses} shift->head->get('To') }

#-------------------------------------------

=method cc

Returns the addresses which are specified on the C<Cc> header line(s)
A list of Mail::Address objects is returned.  C<Cc> stands for
I<Carbon Copy>; the people addressed on this line receive the message
informational, and are usually not expected to reply on its content.

=cut

sub cc() { map {$_->addresses} shift->head->get('Cc') }

#-------------------------------------------

=method bcc

Returns the addresses which are specified on the C<Bcc> header line(s)
A list of Mail::Address objects is returned.
C<Bcc> stands for I<Blind Carbon Copy>: destinations of the message which are
not listed in the messages actually sent.  So, this field will be empty
for received messages, but may be present in messages you construct yourself.

=cut

sub bcc() { map {$_->addresses} shift->head->get('Bcc') }

#-------------------------------------------

=method date

Returns the last C<Date> header line as string.

=example

 my $date = $message->date;

=cut

sub date() { shift->head->get('Date') }

#-------------------------------------------

=method destinations

Returns a list of Mail::Address objects which contains the combined info
of active C<To>, C<Cc>, and C<Bcc> addresses.  Doubles are removed.

=cut

sub destinations()
{   my $self = shift;
    my %to = map { ($_->address => $_) } $self->to, $self->cc, $self->bcc;
    values %to;
}

#-------------------------------------------

=method subject

Returns the message's subject, or the empty string.

=example

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

=examples

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

=head2 The Body

=cut

#------------------------------------------

=method body [BODY]

Return the body of this message.  BE WARNED that this returns
you an object which may be encoded: use decoded() to get a body
with usable data.

With options, a new BODY is set for this message.  This is B<not>
for normal use unless you understand the consequences: you change
the message content without changing the message-ID.  The right
way to go is via

 $message = Mail::Message->buildFromBody($body);  # or
 $message = Mail::Message->build($body);          # or
 $message = $origmsg->forward(body => $body);

The BODY must be an (sub-)class of Mail::Message::Body.  In this case,
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

 my $new       = Mail::Message::Body->new(mime_type => 'text/html');
 my $converted = $msg->body($new);

=cut
  
my @bodydata_in_header = qw/Content-Type Content-Transfer-Encoding
    Content-Length Content-Disposition Lines/;

sub body(;$@)
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my ($rawbody, %args) = @_;
    unless(defined $rawbody)
    {   # Disconnect body from message.
        my $body = delete $self->{MM_body};
        if(defined(my $head = $self->head))
        {   $head->reset($_) foreach @bodydata_in_header;
        }

        $body->message(undef) if defined $body;
        return $body;
    }

    $self->log(INTERNAL => "wrong type of body for $rawbody")
        unless ref $rawbody && $rawbody->isa('Mail::Message::Body');

    # Bodies of real messages must be encoded for safe transmission.
    # Message parts will get encoded on the moment the whole multipart
    # is transformed into a real message.
    my $body = $self->isPart ? $rawbody : $rawbody->encoded;

    my $oldbody = $self->{MM_body};
    return $body if defined $oldbody && $body==$oldbody;

    # Update the header fields to the data of the body message.

    my $head = $self->head;
    confess unless defined $head;

    $head->set($body->type);

    my $body_lines = $body->nrLines;
    my $body_size  = $body->size;
    $body_size    += $body_lines if $crlf_platform;

    $head->set('Content-Length' => $body_size);
    $head->set(Lines            => $body_lines);

    $head->set($body->transferEncoding);
    $head->set($body->disposition);

    # Finally, add the body to the message.

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
will be the type of the body returned.  BODYTYPE extends Mail::Message::Body.

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
dedicated manual page Mail::Message::Body::Encode.  The OPTIONS which
can be specified here are those of the Mail::Message::Body::encode() method.

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

=method parts ['ALL'|'ACTIVE'|'DELETED'|'RECURSE'|FILTER]

Returns the I<parts> of this message. Usually, the term I<part> is used
with I<multipart> messages: messages which are encapsulated in the body
of a message.  To abstract this concept: this method will return you
all header-body combinations which are stored within this message.
Objects returned are Mail::Message's and Mail::Message::Part's.

The option default to 'ALL', which will return the message itself for
single-parts, the nested content of a message/rfc822 object, respectively
the parts of a multipart without recursion.  In case of 'RECURSE', the
parts of multiparts will be collected recursively.  This option cannot
be combined with the other options, which you may want: it that case
you have to test yourself.

'ACTIVE' and 'DELETED' check for the deleted flag on messages and
message parts.  The FILTER is a code reference, which is called for
each message and message part (implies RECURSE).

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
    my $recurse = $what eq 'RECURSE';

    my @parts
     = $body->isNested     ? $body->nested->parts($what)
     : $body->isMultipart  ? $body->parts($recurse ? 'RECURSE' : ())
     :                       $self;

      ref $what eq 'CODE' ? (grep {$what->($_)} @parts)
    : $what eq 'ACTIVE'   ? (grep {not $_->deleted } @parts)
    : $what eq 'DELETED'  ? (grep { $_->deleted } @parts)
    : $what eq 'ALL'      ? @parts
    : $recurse            ? @parts
    : confess "Select parts via $what?";
}

#------------------------------------------

=head2 Labels

=cut

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

=head2 Reading and Writing [internals]

=cut

#------------------------------------------
# All next routines try to create compatibility with release < 2.0
sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#------------------------------------------

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;
    require Mail::Message::Construct;

    no strict 'refs';
    return $self->$call(@_) if $self->can($call);

    our @ISA;                    # produce error via Mail::Reporter
    $call = "${ISA[0]}::$call";
    $self->$call(@_);
}

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
      || $self->{MM_head_type}
      || 'Mail::Message::Head::Complete';

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
        my $type = defined $ct ? lc $ct->body : 'text/plain';

        # Be sure you have acceptable bodies for multipars and nested.
        if(substr($type, 0, 10) eq 'multipart/' && !$bodytype->isMultipart)
        {   $bodytype = $mpbody }
        elsif($type eq 'message/rfc822' && !$bodytype->isNested)
        {   $bodytype = $nbody  }

        $body = $bodytype->new
        ( message           => $self
        , mime_type         => scalar $head->get('Content-Type')
        , transfer_encoding => scalar $head->get('Content-Transfer-Encoding')
        , disposition       => scalar $head->get('Content-Disposition')
        , checked           => $self->{MM_trusted}
        , $self->logSettings
        );
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

Where the body() method can be used to set and get a body, with all
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

=method labelsToStatus

When the labels were changes, there may be an effect for the
C<Status> and/or C<X-Status> header-lines.  Whether this update has
to take place depends on the type of folder.

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

Update the labels according the status lines in the header.

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

1;
