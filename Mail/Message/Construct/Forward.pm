
use strict;

package Mail::Message;

use Mail::Message::Body::Multipart;
use Mail::Address;
use Scalar::Util 'blessed';

=chapter NAME

Mail::Message::Construct::Forward - forwarding a Mail::Message

=chapter SYNOPSIS

 my Mail::Message $forward = $message->forward(To => 'you');
 $forward->send;

=chapter DESCRIPTION

Complex functionality on M<Mail::Message> objects is implemented in
different files which are autoloaded.  This file implements the
functionality related to creating forwarded message.

=chapter METHODS

=section Constructing a message

=method forward OPTIONS

Forward the content of this message.  The body of the message to be forwarded
is encapsulated in some accompanying text (if you have no wish for that, than
C<bounce> is your choice).

You may forward a whole message, but also message parts.
You may wish to overrule some of the default header settings for the
reply immediately, or you may do that later with C<set> on the header.

=option  body OBJECT
=default body undef

If you specify a fully prepared body OBJECT, it will be used as forwarded
message contents.  In this case, only the headers are constructed for you.

=option  include 'INLINE'|'ATTACH'
=default include C<'INLINE'>

Must the message where this is a reply to be included in the message?
With C<INLINE> a forward body is composed. C<ATTACH> will create a multi-part
body, where the original message is added after the specified body.  It is
only possible to inline textual messages, therefore binary or multi-part
messages will always be enclosed as attachment.

=option  message_type CLASS
=default message_type M<Mail::Message>

Create a message with the requested type.  By default, it will be a
M<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=option  max_signature INTEGER
=default max_signature C<10>

Passed to M<Mail::Message::Body::stripSignature(max_lines)>.  Only
effective for single-part messages.

=option  prelude BODY
=default prelude undef

The line(s) which will be added before the quoted forwarded lines.
If nothing is specified, the result of the M<forwardPrelude()> method
is used.  When C<undef> is specified, no prelude will be added.

=option  postlude BODY
=default postlude undef

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.  This should not include the signature, which has its
own option.  The signature will be added after the postlude when the
forwarded message is C<INLINE>d.

=option  quote CODE|STRING
=default quote undef

Mangle the lines of an C<INLINE>d reply with CODE, or by prepending a
STRING to each line.  The routine specified by CODE is called when the
line is in C<$_>.

By default, nothing is added before each line.  This option is processed
after the body has been decoded.

=option  signature BODY|MESSAGE
=default signature undef

The signature to be added in case of a multi-part forward.  The mime-type
of the signature body should indicate this is a used as such.  However,
in INLINE mode, the body will be taken, a line containing C<'-- '> added
before it, and added behind the epilogue.

=option  strip_signature REGEXP|STRING|CODE
=default strip_signature C<qr/^--\s/>

Remove the signature of the sender.  The value of this parameter is
passed to M<Mail::Message::Body::stripSignature(pattern)>, unless the
source text is not included.  The signature is stripped from the message
before quoting.

When a multi-part body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=requires To ADDRESSES

The destination of your message. Obligatory.  The ADDRESSES may be
specified as string, a M<Mail::Address> object, or as array of
M<Mail::Address> objects.

=option  From ADDRESSES
=default From <'to' in current>

Your identification, by default taken from the C<To> field of the
source message.

=option  Bcc ADDRESSES
=default Bcc undef

Receivers of blind carbon copies: their names will not be published to
other message receivers.

=option  Cc ADDRESSES
=default Cc undef

The carbon-copy receivers, by default none.

=option  Date DATE
=default Date <now>

The date to be used in the message sent.

=option  Message-ID STRING
=default Message-ID <uniquely generated>

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=option  Subject STRING|CODE
=default Subject M<forwardSubject()>

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the M<forwardSubject()> method is used.

=error Cannot include forward source as $include.

Unknown alternative for the M<forward(include)>.  Valid choices are
C<NO>, C<INLINE>, and C<ATTACH>.

=error No address to create forwarded to.

If a forward message is created, a destination address must be specified.

=cut

# tests in t/57forw1f.t

sub forward(@)
{   my ($self, %args) = @_;

    my $include  = $args{include} || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    unless($include eq 'INLINE' || $include eq 'ATTACH')
    {   $self->log(ERROR => "Cannot include forward source as $include.");
        return;
    }

    my @stripopts =
     ( pattern     => $args{strip_signature}
     , max_lines   => $args{max_signature}
     );

    my $decoded  = $body->decoded;
    $body        = $strip ? $decoded->stripSignature(@stripopts) : $decoded;

    if($body->isMultipart && $body->parts==1)
    {   $decoded = $body->part(0)->decoded;
        $body    = $strip ? $decoded->stripSignature(@stripopts) : $decoded;
    }

    if($include eq 'INLINE' && $body->isMultipart)
    {    $include = 'ATTACH' }
    elsif($include eq 'INLINE' && $body->isBinary)
    {   $include = 'ATTACH';
        $body    = Mail::Message::Body::Multipart->new(parts => [$body]);
    }

    if($include eq 'INLINE')
    {   if(defined(my $quote = $args{quote}))
        {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
            $body = $body->foreachLine($quoting);
        }
    }

    #
    # Collect header info
    #

    my $mainhead = $self->toplevel->head;

    # Where it comes from
    my $from = $args{From};
    unless(defined $from)
    {   my @from = $self->to;
        $from    = \@from if @from;
    }

    # To whom to send
    my $to = $args{To};
    $self->log(ERROR => "No address to create forwarded to."), return
       unless $to;

    # Create a subject
    my $subject = $args{Subject};
    if(!defined $subject) { $subject = $self->forwardSubject($subject) }
    elsif(ref $subject)   { $subject = $subject->($subject) }

    # Create a nice message-id
    my $msgid   = $args{'Message-ID'} || $mainhead->createMessageId;
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    # Prelude
    my $prelude = exists $args{prelude} ? $args{prelude}
       : $self->forwardPrelude;

    $prelude     = Mail::Message::Body->new(data => $prelude)
        if defined $prelude && ! blessed $prelude;
 
    # Postlude
    my $postlude = exists $args{postlude} ? $args{postlude}
       : $self->forwardPostlude;

    $postlude    = Mail::Message::Body->new(data => $postlude)
        if defined $postlude && ! blessed $postlude;

    #
    # Create the message.
    #

    my $total;
    if($include eq 'INLINE')
    {   my $signature = $args{signature};
        $signature = $signature->body
           if defined $signature && $signature->isa('Mail::Message');

        $total = $body->concatenate
          ( $prelude, $body, $postlude
          , (defined $signature ? "--\n" : undef), $signature
          );
    }
    if($include eq 'ATTACH')
    {
         my $intro = $prelude->concatenate
           ( $prelude
           , [ "\n", "[Your message is attached]\n" ]
           , $postlude
           );

        $total = Mail::Message::Body::Multipart->new
         ( parts => [ $intro, $body, $args{signature} ]
        );
    }

    my $msgtype = $args{message_type} || 'Mail::Message';

    my $reply   = $msgtype->buildFromBody
      ( $total
      , From        => $from || '(undisclosed)'
      , To          => $to
      , Subject     => $subject
      , References  => ($refs ? "$origid $refs" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc   => $args{Cc}  ) if $args{Cc};
    $newhead->set(Bcc  => $args{Bcc} ) if $args{Bcc};
    $newhead->set(Date => $args{Date}) if $args{Date};

    # Ready

    $self->log(PROGRESS => 'Forward created from '.$origid);
    $reply;
}

#------------------------------------------

=method forwardSubject STRING

Create a subject for a message which is a forward from this one.  This routine
tries to count the level of reply in subject field, and transform it into
a standard form.  Please contribute improvements.

=examples

 subject                 --> Forw: subject
 Re: subject             --> Forw: Re: subject
 Re[X]: subject          --> Forw: Re[X]: subject
 <blank>                 --> Forwarded

=cut

# tests in t/57forw0s.t

sub forwardSubject($)
{   my ($self, $subject) = @_;
    defined $subject && length $subject ? "Forw: $subject" : "Forwarded";
}

#------------------------------------------

=method forwardPrelude

Create a few lines to be included before the forwarded message
content.  The return is an array of lines.

=examples

 ---- BEGIN forwarded message
 From: him@somewhere.else.nl (Original Sender)
 To: me@example.com (Me the receiver)
 Cc: the.rest@world.net
 Date: Wed, 9 Feb 2000 15:44:05 -0500
 <blank line>

=cut

sub forwardPrelude()
{   my $head  = shift->head;

    my @lines = "---- BEGIN forwarded message\n";
    my $from  = $head->get('from');
    my $to    = $head->get('to');
    my $cc    = $head->get('cc');
    my $date  = $head->get('date');

    push @lines, $from->string if defined $from;
    push @lines,   $to->string if defined $to;
    push @lines,   $cc->string if defined $cc;
    push @lines, $date->string if defined $date;
    push @lines, "\n";

    \@lines;
}

#------------------------------------------

=method forwardPostlude

Added after the forwarded message.

=examples

 ---- END forwarded message

=cut

sub forwardPostlude()
{   my $self = shift;
    my @lines = ("---- END forwarded message\n");
    \@lines;
}
 
1;
