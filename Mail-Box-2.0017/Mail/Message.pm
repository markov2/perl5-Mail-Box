use strict;
use warnings;

package Mail::Message;
use base 'Mail::Reporter';

use Mail::Message::Part;
use Mail::Message::Head::Complete;

use Carp;

our $VERSION = 2.00_17;

=head1 NAME

Mail::Message - general message object

=head1 CLASS HIERARCHY

 Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open(folder => $MAIL);
 my $msg    = $folder->message(2);    # $msg isa Mail::Message

 $msg->decoded->print($outfile);

 my Mail::Message $construct  = Mail::Message->new;
 my Mail::Message $construct  = Mail::Message->build(...);
 my Mail::Message::Head $head = $msg->head;
 my Mail::Message::Body $body = $msg->decoded;
 my $subject = $msg->get('subject');

=head1 DESCRIPTION

A C<Mail::Message> object is a container for message information read from a
file.  Everything what is not folder related will be found here.

Complex message handling (like construction of replies) are handled by the
C<Mail::Message::Construct> package which is autoloaded.  That package
adds functionality to the C<Mail::Message> objects.

The main methods are C<get()> -to get information from a message
header- and C<decoded()> to get the intented content of a message.

=head1 METHOD INDEX

The general methods for C<Mail::Message> objects:

  MMC bounce OPTIONS                       nrLines
  MMC build [MESSAGE|BODY], CONTENT        parent
  MMC buildFromBody BODY, HEADERS          parts
      decoded OPTIONS                      print [FILEHANDLE]
      encode OPTIONS                   MMC quotePrelude [STRING|FIELD]
   MR errors                           MMC reply OPTIONS
      get FIELD                        MMC replySubject STRING
      guessTimestamp                    MR report [LEVEL]
      isDummy                           MR reportAll [LEVEL]
      isMultipart                          send [MAILER], OPTIONS
      isPart                               size
   MR log [LEVEL [,STRINGS]]               timestamp
      messageId                            toplevel
      modified [BOOL]                   MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
      DESTROY                           MR logSettings
      body [BODY]                       MR notImplemented
      clone                                read PARSER, [BODYTYPE]
      coerce MESSAGE                       readBody PARSER, HEAD [, BO...
      head [HEAD]                          readHead PARSER [,CLASS]
   MR inGlobalDestruction                  storeBody BODY
      isDelayed                            takeMessageId [STRING]

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMC = L<Mail::Message::Construct>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message object.  The message's head and body will
be read later, unless specified at construction.

 OPTION            DESCRIBED IN       DEFAULT
 body              Mail::Message      undef
 body_type         Mail::Message      'Mail::Message::Body::Lines'
 head              Mail::Message      undef
 head_type         Mail::Message      'Mail::Message::Head::Complete'
 log               Mail::Reporter     'WARNINGS'
 messageId         Mail::Message      undef
 modified          Mail::Message      0
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Message      0
 head_wrap         Mail::Message      72

=over 4

=item * body =E<gt> OBJECT

Instantiate the message with a body which has been created somewhere
before the message is constructed.  The OBJECT must be a sub-class
of C<Mail::Message::Body>.

=item * body_type =E<gt> CLASS

Default type of body to be created for C<readBody()>.

=item * head =E<gt> OBJECT

Instantiate the message with a head which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of C<Mail::Message::Head>.

=item * head_type =E<gt> CLASS

Default type of head to be created for C<readHead()>.

=item * head_wrap E<gt> WIDTH

The soft maximum line width of header lines in the folder to write.

=item * messageId =E<gt> STRING

The id on which this message can be recognized.  If none specified and
not defined in the header --but one is needed-- there will be one assigned
to the message to be able to pass unique message-ids between objects.

=item * modified =E<gt> BOOL

Flags this message as being modified, from the beginning on.  Usually,
modification is auto-detected, but there may be reasons to be extra
explicit.

=item * trusted =E<gt> BOOL

Is this message from a trusted source?  If not, the content must be
checked before use.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MM_modified}  = $args->{modified}  || 0;
    $self->{MM_head_wrap} = $args->{head_wrap} || 72;
    $self->{MM_trusted}   = $args->{trusted}   || 0;

    # Set the header

    my $head;
    if($head = $args->{head})
    {   $self->head($head);
    }
    elsif(my $msgid = $args->{messageId} || $args->{messageID})
    {   $self->takeMessageId($msgid);
    }

    # Set the body
    if(my $body = $args->{body})
    {   $self->{MM_body} = $body;
        $body->message($self);
    }

    $self->{MM_body_type} = $args->{body_type}
       if $args->{body_type};

    $self->{MM_head_type} = $args->{head_type}
       if $args->{head_type};

    $self;
}

#------------------------------------------

=item get FIELD

Returns the value which is stored in the header FIELD with the specified
name.  If no header is known yet, or the field is not defined, then
C<undef> is returned.  If the field has multiple appearances in the
header, the last instance is returned.

The field name is case insensitive.  Only the `body' of the field is
returned, not the comment (after ';').  If you need more complex handing
of fields, then call

Example:

 print $msg->get('Content-Type'), "\n";

Is equivalent to:

 print $msg->head->get('Content-Type')->body, "\n";

=cut

sub get($)
{   my $head  = shift->head || return;
    my $field = $head->get(shift) || return;
    $field->body;
}

#------------------------------------------

=item decoded OPTIONS

Decodes the body of this message, and returns it as a body object.  If there
was no encoding, the body object as read from file is passed on, however,
some more work will be needed when a serious encoding is encountered.
The OPTIONS control how the conversion takes place.

 OPTION            DESCRIBED IN          DEFAULT
 keep              Mail::Message         0
 result_type       Mail::Message         <type of the body>

=over 4

=item * keep =E<gt> BOOL

Controls whether the decoded result will be kept.  If not, the decoding
may be performed more than once.  However, it will consume extra
resources...

=item * result_type =E<gt> BODYTYPE

Specifies which kind of body should be used for the final result, and
eventual intermediate conversion stages.  It is not sure that this
will be the type of the body returned.  BODYTYPE extends C<Mail::Message:Body>.

=back

Examples:

   $message->decoded->print(\*STDOUT);

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

=item encode OPTIONS

Encode the message to a certain format.  Read the details in the
dedicated manual page C<Mail::Message::Body::Encode>.  The OPTIONS which
can be specified here are those of the C<encode()> method.

=cut

sub encode(@)
{   my $body = shift->body->load;
    $body ? $body->encode(@_) : undef;
}

#-------------------------------------------

=item modified [BOOL]

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

=item parent

=item isPart

=item toplevel

If the message is a part of another message, C<parent> returns the reference
to the containing message. C<parent> returns C<undef> if the message is not a
part, but rather the main message.  C<isPart> returns true if the message
is a part of another message.  C<toplevel> returns a reference to the main
message, which will be the current message if the message is not part of
another message.

Examples:

    my Mail::Message $msg = ...

    return unless $msg->body->isMultipart;
    my $part   = $msg->body->part(2);

    return unless $part->body->isMultipart;
    my $nested = $part->body->part(3);

    $nested->parent;     # returns $part
    $nested->toplevel;   # returns $msg
    $msg->parent;        # returns undef
    $msg->toplevel;      # returns $msg
    $msg->isPart;        # returns false
    $part->isPart;       # returns true

=cut

sub parent()     { undef }   # overridden by Mail::Message::Part
sub toplevel()   { shift }   # idem
sub isPart()     { 0 }       # idem

#-------------------------------------------

=item messageId

Retrieve the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

sub messageId() { $_[0]->{MM_message_id} || $_[0]->takeMessageId}
sub messageID() {shift->messageId}   # compatibility

#-------------------------------------------

=item guessTimestamp

Return an estimate on the time this message was sent.  The data is
derived from the header, where it can be derived from the C<date> and
C<received> lines.  For MBox-like folders you may get the date from
the from-line as well.

This method may return C<undef> if the header is not parsed or only
partially known.  If you require a time, then use the C<timestamp()>
method, described below.

Examples:

    print "Receipt ", ($message->timestamp || 'unknown'), "\n";

=cut

sub guessTimestamp() {shift->head->guessTimestamp}

#-------------------------------------------

=item timestamp

Get a timestamp, doesn't matter how much work it is.  If it is impossible
to get a time from the header-lines, the current time-of-living is taken.

=cut

sub timestamp() {shift->head->timestamp}

#------------------------------------------

=item isDummy

Dummy messages are used to fill holes in linked-list and such, where only
a message-id is known, but not the place of the header of body data.

This method is also available for C<Mail::Message::Dummy> objects, where
this will return C<true>.  On any extention of C<Mail::Message>, this will
return C<false>.

=cut

sub isDummy()    { 0 }

#------------------------------------------

=item isMultipart

Check whether this message is a multipart message (has attachments).  To
find this out, we need at least the header of the message; there is no
need to read the body of the message to detect this.

=cut

sub isMultipart() {shift->body->isMultipart}

#------------------------------------------

=item parts

Returns the parts of this message.  If the message is not a multi-part, it
will be returned itself.  However, if this is a multi-part then a list
with all the parts is returned.

=cut

sub parts()
{   my $self = shift;
    $self->isMultipart ? $self->body->parts : $self;
}

#------------------------------------------
# All next routines try to create compatibility with release < 2.0

sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#------------------------------------------

=item print [FILEHANDLE]

Print the message to the FILE-HANDLE, which defaults to STDOUT.
If the message was modified, it comes from the modified structures in
memory.  Preferably, however, a folder-to-folder copy of bytes is
tried: it is much faster.  I this case, printing will not trigger the
loading of the message to memory.

Examples:

 $message->print(\*STDERR);
 $message->print;

 my $out = IO::File->new('out', 'w');
 $message->print($out);

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------

=item send [MAILER], OPTIONS

Transmit the message to anything outside this Perl program.  Writing

 my $mailer = Mail::Transport::SMTP->new(@smtpopts);
 $message->send($mailer, @sendopts);

is a short for

 my $mailer = Mail::Transport::SMTP->new(@smtpopts);
 $mailer->send($message, @sendopts);

However, when the MAILER is not specified, one will be auto-generated
via C<Mail::Transport::new>.  This object will be re-used. For instance

 $message->send(@sendopts);

is equivalent to

 Mail::Transport->new->send($message, @sendopts);

The OPTIONS are mailer specific.

=cut

my $default_mailer;

sub send(@)
{   my $self   = shift;

    require Mail::Transport;

    my $mailer
       = ref $_[0] && $_[0]->isa('Mail::Transport') ? shift
       : defined $default_mailer                    ? $default_mailer
       : ($default_mailer = Mail::Transport->new(@_));

    croak "No mailer found" unless defined $mailer;

    $mailer->send($self, @_);
}

#------------------------------------------

=item size

Returns the size of the whole message in bytes.

=cut

sub size()
{   my $self = shift;
    $self->head->size + $self->body->size;
}

#------------------------------------------

=item nrLines

Returns the number of lines used for the whole message.

=cut

sub nrLines()
{   my $self = shift;
    $self->head->nrLines + $self->body->nrLines;
}

#------------------------------------------

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;
    require Mail::Message::Construct;

    no strict 'refs';
    return $self->$call(@_) if $self->can($call);

    our @ISA;
    $call = "${ISA[0]}::$call";
    $self->$call(@_);
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item clone

Create a copy of this message.  The head and body, the log
and trace levels are taken.  The copy will not be added to
any folder automatically.
 
Example:

   $copy = $msg->clone;

See also the C<copyTo FOLDER>, C<moveTo FOLDER>, and C<reply> methods.

=cut

sub clone()
{   my $self  = shift;
    my $class = ref $self;

    # First clone body, which may trigger head load as well.  If head is
    # triggered first, then it may be decided to be lazy on the body at
    # moment.  And then the body would be triggered.

    $class->new
     ( body  => $self->body->clone
     , head  => $self->head->clone
     , $self->logSettings
     );
}

#------------------------------------------

=item read PARSER, [BODYTYPE]

Read one message from file.  The PARSER is opened on the file.  First
C<readHeader> is called, and the head is stored in the message.  Then
C<readBody> is called, to produce a body.  Also the body is added to
the message without decodings being done.

The optional BODYTYPE may be a body class or a reference to a code
which returns a body-class based on the header.

=cut

sub read($;$)
{   my ($self, $parser, $bodytype) = @_;

    my $head         = $self->readHead($parser) or return;
    $self->head($head);
#warn "Subject: ", $self->get('subject'), "\n";

    $self->{MM_body} = $self->readBody($parser, $head, $bodytype);
    $self;
}

#------------------------------------------

=item readHead PARSER [,CLASS]

Read a head into an object of the specified CLASS.  The CLASS defaults to
the C<head_type> option specified at creation of the message (see C<new>).
The PARSER is the access to the folder's file.

=cut

sub readHead($;$)
{   my ($self, $parser) = (shift, shift);
    my $headtype = shift || $self->{MM_head_type}
                   || 'Mail::Message::Head::Complete';

    $headtype->new
      ( message     => $self
      , wrap_length => delete $self->{MM_head_wrap}
      , $self->logSettings
      )->read($parser);
}


#------------------------------------------

=item readBody PARSER, HEAD [, BODYTYPE]

Read a body of a message.  The PARSER is the access to the folder's
file, and the HEAD is already read.  Information from the HEAD is used
to create expectations about the message's length, but also to determine
the mime-type and encodings of the body data.

The BODYTYPE determines which kind of body will be made and defaults to
the value specified by the C<body_type> option at message creation
(see C<new>).  BODYTYPE may be the name of a body class, or a reference
to a routine which returns the body's class when passed the HEAD as only
argument.

=cut

sub readBody($$;$)
{   my ($self, $parser, $head, $getbodytype) = @_;

    my $bodytype
      = ! $getbodytype   ? ($self->{MM_body_type}||'Mail::Message::Body::Lines')
      : ref $getbodytype ? $getbodytype->($self, $head)
      :                    $getbodytype;

    my $lines   = $head->get('Lines');
    my $size    = $head->guessBodySize;

    $bodytype->new
      ( message           => $self
      , mime_type         => ($head->get('Content-Type')              || undef)
      , transfer_encoding => ($head->get('Content-Transfer-Encoding') || undef)
      , disposition       => ($head->get('Content-Disposition')       || undef)
      , checked           => $self->{MM_trusted}
      , $self->logSettings
      )->read
      ( $parser, $head, $getbodytype,
      , (defined $lines ? int $lines->body : undef)
      , $size
      );
}

#------------------------------------------

=item body [BODY]

Return the body of this message.  BE WARNED that this returns
you an object which may be encoded: use C<decoded> to get a body
with usable data.

With options, a new BODY is set for this message.  The body must
be an (sub-)class of C<Mail::Message::Body>.  In this case, information
from the specified body will be compied into the header.  The body
object will be encoded if needed, because messages written to file
or transmitted shall not contain binary data.  The converted body
is returned.

When BODY is C<undef>, the current message body will be disected from
the message.  All relation will be cut.  The body is returned, and
can be connected to a diffent message.

Examples:

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
    unless($rawbody)
    {   # Disconnect body from message.
        my $body = delete $self->{MM_body};
        if(my $head = $self->head)
        {   $head->reset($_) foreach @bodydata_in_header;
        }

        $self->modified(1);
        $body->message(undef) if defined $body;
        return $body;
    }

    $self->log(INTERNAL => "wrong type of body for $rawbody")
        unless ref $rawbody && $rawbody->isa('Mail::Message::Body');

    # Convert the body to something what is acceptable in transmitted
    # and saved messages.

    my $body = $rawbody->encoded;

    my $oldbody = $self->{MM_body};
    return $body if defined $oldbody && $body==$oldbody;

    # Update the header fields to the data of the body message.

    my $head = $self->head;
    $head->set($body->type);
    $head->set('Content-Length' => $body->size);
    $head->set('Lines'          => $body->nrLines);
    $head->set($body->transferEncoding);
    $head->set($body->disposition);

    # Finally, add the body to the message.

    $body->message($self);
    $body->modified(1) if defined $oldbody;

    $self->{MM_body} = $body;
}

#------------------------------------------

=item storeBody BODY

Where the C<body()> method can be used to set and get a body, with all
the necessary checks, this method is bluntly adding the specified body
to the message.  No conversions, not checking.

=cut

sub storeBody($)
{   my ($self, $body) = @_;
    $self->{MM_body} = $body;
    $body->message($self);
    $body;
}

#------------------------------------------

=item head [HEAD]

Return (optionally after setting) the HEAD of this message.
The head must be an (sub-)class of C<Mail::Message::Head>.

Example:

    my $head = $msg->head(new Mail::Message::Head);

=cut

sub head(;$)
{   my $self = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    return delete $self->{MM_head} unless $head;

    $self->log(INTERNAL => "wrong type of head for $self")
        unless ref $head && $head->isa('Mail::Message::Head');

    $head->message($self);

    my $old = $self->{MM_head};
    $self->{MM_modified}++ if $old && !$old->isDelayed;

    $self->{MM_head} = $head;

    $self->takeMessageId
        unless $head->isDelayed;

    $head;
}

#-------------------------------------------

=item isDelayed

Check whether the message is delayed (not yet read from file).  Returns
true or false, dependent on the body type.

=cut

sub isDelayed()
{    my $body = shift->body;
     !$body || $body->isDelayed;
}

#------------------------------------------

=item takeMessageId [STRING]

Take the message-id from the STRING, or create one when the C<undef>
is specified.  If not STRING nor C<undef> is given, the current header
of the message is requested for the value of the C<'Message-ID'> field.

Angles (if present) are removed from the id. 

=cut

sub takeMessageId(;$)
{   my $self = shift;
    my $msgid = @_ ? shift : $self->get('Message-ID');

    return $self->{MM_message_id} = $self->head->createMessageId
        unless defined $msgid;
    
    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }

    $self->{MM_message_id} = $msgid;
}

#------------------------------------------

=item coerce MESSAGE

(Class method) Coerce a MESSAGE into a C<Mail::Message>.  In some
occations, for instance where you add a message to a folder, this
coercion is automatically called to ensure that the correct message
type is stored.

The coerced message is returned on success, otherwise C<undef>.  The
coerced message may be a reblessed version of the original message
or a new object.

Valid MESSAGEs which can be coerced into C<Mail::Message> objects
are of type

=over 4

=item * C<MIME::Entity>'s, using C<Mail::Message::Convert::MimeEntity>

=item * C<Mail::Internet>'s, using C<Mail::Message::Convert::MimeEntity>

=item * any extension of C<Mail::Message> is left untouched

=back

Example:

   my $message = Mail::Message->new(...);
   my $coerced = Mail::Box::MBox::Message->coerce($message);
   # now $coerced is a Mail::Box::Mbox::Message

It is better to use (when the message will be stored in that folder):

   my $folder  = Mail::Box::Mbox->new;
   my $coerced = $folder->coerce($message);
   my $coerced = $folder->addMessage($message);

=cut

my $mail_internet_converter;
my $mime_entity_converter;

sub coerce($)
{   my ($class, $message) = @_;

confess "@_" unless $message;
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
    {   confess "Cannot coerce ".ref($message)." objects into "
              . __PACKAGE__." objects.\n";
    }

    bless $message, $class;
}

#------------------------------------------

=item DESTROY

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

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
