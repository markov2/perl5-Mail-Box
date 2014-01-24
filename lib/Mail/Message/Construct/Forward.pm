
use strict;

package Mail::Message;

use Mail::Message::Body::Multipart;
use Mail::Message::Body::Nested;
use Scalar::Util 'blessed';

=chapter NAME

Mail::Message::Construct::Forward - forwarding a Mail::Message

=chapter SYNOPSIS

 my Mail::Message $forward = $message->forward(To => 'you');
 $forward->send;

=chapter DESCRIPTION

Complex functionality on M<Mail::Message> objects is implemented in
different files which are autoloaded.  This file implements the
functionality related to creating forwarded messages.

=chapter METHODS

=section Constructing a message

=method forward %options

Forward the content of this message.  The body of the message to be forwarded
is encapsulated in some accompanying text (if you have no wish for that, than
C<bounce> is your choice).  A M<Mail::Message> object is returned on success.

You may forward a whole message, but also message parts.
You may wish to overrule some of the default header settings for the
reply immediately, or you may do that later with C<set> on the header.

When a multi-part body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=option  body OBJECT
=default body undef

If you specify a fully prepared body OBJECT, it will be used as forwarded
message contents.  In this case, only the headers are constructed for you.

=option  include 'NO'|'INLINE'|'ATTACH'|'ENCAPSULATE'
=default include <if body then C<'NO'> else C<'INLINE'>>

Must the message where this is a reply to be included in the message?
When C<INLINE> is given, you may pass the options of M<forwardInline()>
as well.

In many applications, the forward option C<as attachment> results in a
structure which is produced when this option is set to C<ENCAPSULATE>.
Their default behavior is usually C<INLINE>.

It is only possible to inline textual messages, therefore binary or
multi-part messages will always be enclosed as attachment.
Read the details in section L</Creating a forward>..

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

Supply a STRING as specific message-id for the forwarded message.
By default, one is generated for you.  If there are no angles around
your id, they will be added.

=option  Subject STRING|CODE
=default Subject M<forwardSubject()>
Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the M<forwardSubject()> method is used.

=option  preamble STRING|BODY
=default preamble C<constructed from prelude and postlude>
Part which is attached before the forwarded message.  If no preamble
is given, then it is constructed from the prelude and postlude.  When
these are also not present, you will still get a one liner: the result
of M<forwardPrelude()>

=option  signature BODY|MESSAGE
=default signature undef

The signature to be added in case of a multi-part forward.  The mime-type
of the signature body should indicate this is a used as such.  However,
in INLINE mode, the body will be taken, a line containing C<'-- '> added
before it, and added behind the epilogue.

=error Cannot include forward source as $include.
Unknown alternative for the M<forward(include)>.  Valid choices are
C<NO>, C<INLINE>, C<ATTACH>, and C<ENCAPSULATE>.

=error No address to create forwarded to.
If a forward message is created, a destination address must be specified.

=cut

# tests in t/57forw1f.t

sub forward(@)
{   my $self    = shift;
    my %args    = @_;

    return $self->forwardNo(@_)
        if exists $args{body};

    my $include = $args{include} || 'INLINE';
    return $self->forwardInline(@_) if $include eq 'INLINE';

    my $preamble = $args{preamble};
    push @_, preamble => Mail::Message::Body->new(data => $preamble)
        if defined $preamble && ! ref $preamble;

    return $self->forwardAttach(@_)      if $include eq 'ATTACH';
    return $self->forwardEncapsulate(@_) if $include eq 'ENCAPSULATE';

    $self->log(ERROR => 'Cannot include forward source as $include.');
    undef;
}

#------------------------------------------

=method forwardNo %options
Construct a forward, where the whole body of the message is already
constructed.  That complex body is usually produced in M<forwardInline()>,
M<forwardAttach()>, or M<forwardEncapsulate()>.

The %options are the same as for C<forward()> except that C<body> is
required.  Some other options, like C<preamble>, are ignored.
=requires body BODY

=cut

sub forwardNo(@)
{   my ($self, %args) = @_;

    my $body = $args{body};
    $self->log(INTERNAL => "No body supplied for forwardNo()")
       unless defined $body;

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
    my $srcsub  = $args{Subject};
    my $subject
     = ! defined $srcsub ? $self->forwardSubject($self->subject)
     : ref $srcsub       ? $srcsub->($self->subject)
     :                     $srcsub;

    # Create a nice message-id
    my $msgid   = $args{'Message-ID'} || $mainhead->createMessageId;
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    my $forward = Mail::Message->buildFromBody
      ( $body
      , From        => ($from || '(undisclosed)')
      , To          => $to
      , Subject     => $subject
      , References  => ($refs ? "$refs $origid" : $origid)
      );

    my $newhead = $forward->head;
    $newhead->set(Cc   => $args{Cc}  ) if $args{Cc};
    $newhead->set(Bcc  => $args{Bcc} ) if $args{Bcc};
    $newhead->set(Date => $args{Date}) if $args{Date};

    # Ready

    $self->label(passed => 1);
    $self->log(PROGRESS => "Forward created from $origid");
    $forward;
}

#------------------------------------------

=method forwardInline %options

This method is equivalent in behavior to M<forward()> with the
option C<include> set to C<'INLINE'>.  You can specify most of
the fields which are available to M<forward()> except
C<include> and C<body>.

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

=option  is_attached STRING
=default is_attached C<"[The forwarded message is attached]\n">
A forward on binary messages can not be inlined.  Therefore, they are
automatically translated into an attachment, as made by M<forwardAttach()>.
The obligatory preamble option to that method may be specified as option
to this method, to be used in case of such a forward of a binary, but
is otherwise constructed from the prelude, the value of this option, and
the postlude.

=option  strip_signature REGEXP|STRING|CODE
=default strip_signature C<qr/^--\s/>
Remove the signature of the sender.  The value of this parameter is
passed to M<Mail::Message::Body::stripSignature(pattern)>, unless the
source text is not included.  The signature is stripped from the message
before quoting.

=cut

sub forwardInline(@)
{   my ($self, %args) = @_;

    my $body     = $self->body;

    while(1)    # simplify
    {   if($body->isMultipart && $body->parts==1)
                               { $body = $body->part(0)->body }
        elsif($body->isNested) { $body = $body->nested->body }
        else                   { last }
    }

    # Prelude must be a real body, otherwise concatenate will not work
    my $prelude = exists $args{prelude} ? $args{prelude}
       : $self->forwardPrelude;

    $prelude     = Mail::Message::Body->new(data => $prelude)
        if defined $prelude && ! blessed $prelude;
 
    # Postlude
    my $postlude = exists $args{postlude} ? $args{postlude}
       : $self->forwardPostlude;
 
    # Binary bodies cannot be inlined, therefore they will be rewritten
    # into a forwardAttach... preamble must replace prelude and postlude.

    if($body->isMultipart || $body->isBinary)
    {   $args{preamble} ||= $prelude->concatenate
           ( $prelude
           , ($args{is_attached} || "[The forwarded message is attached]\n")
           , $postlude
           );
        return $self->forwardAttach(%args);
    }
    
    $body        = $body->decoded;
    my $strip    = (!exists $args{strip_signature} || $args{strip_signature})
                && !$body->isNested;

    $body        = $body->stripSignature
      ( pattern     => $args{strip_signature}
      , max_lines   => $args{max_signature}
      ) if $strip;

    if(defined(my $quote = $args{quote}))
    {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
        $body = $body->foreachLine($quoting);
    }

    #
    # Create the message.
    #

    my $signature = $args{signature};
    $signature = $signature->body
        if defined $signature && $signature->isa('Mail::Message');

    my $composed  = $body->concatenate
      ( $prelude, $body, $postlude
      , (defined $signature ? "-- \n" : undef), $signature
      );

    $self->forwardNo(%args, body => $composed);
}

#------------------------------------------

=method forwardAttach %options
Forward the message as I<flat> attachment to the specified C<preamble>.  You
can specify all options available to C<forward()>, although a C<preamble>
which is provided as body object is required, and any specified C<body>
is ignored.

=requires preamble BODY|PART
=error Method forwardAttach requires a preamble

=cut

sub forwardAttach(@)
{   my ($self, %args) = @_;

    my $body  = $self->body;
    my $strip = !exists $args{strip_signature} || $args{strip_signature};

    if($body->isMultipart)
    {   $body = $body->stripSignature if $strip;
        $body = $body->part(0)->body  if $body->parts == 1;
    }

    my $preamble = $args{preamble};
    $self->log(ERROR => 'Method forwardAttach requires a preamble'), return
       unless ref $preamble;

    my @parts = ($preamble, $body);
    push @parts, $args{signature} if defined $args{signature};
    my $multi = Mail::Message::Body::Multipart->new(parts => \@parts);

    $self->forwardNo(%args, body => $multi);
}

#------------------------------------------

=method forwardEncapsulate %options
Like M<forwardAttach()>, but in this case the original message is first
encapsulated as nested message in a M<Mail::Message::Body::Nested>, and
then joint into a multipart.

You can specify all options available to C<forward()>, although a C<preamble>
which is provided as body object is required, and any specified C<body>
is ignored.  Signatures are not stripped.  Signatures are not stripped.

=requires preamble BODY|PART
=error Method forwardEncapsulate requires a preamble

=cut

sub forwardEncapsulate(@)
{   my ($self, %args) = @_;

    my $preamble = $args{preamble};
    $self->log(ERROR => 'Method forwardEncapsulate requires a preamble'), return
       unless ref $preamble;

    my $nested= Mail::Message::Body::Nested->new(nested => $self->clone);
    my @parts = ($preamble, $nested);
    push @parts, $args{signature} if defined $args{signature};

    my $multi = Mail::Message::Body::Multipart->new(parts => \@parts);

    $self->forwardNo(%args, body => $multi);
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

#------------------------------------------

=chapter DETAILS

=section Creating a forward

The main difference between M<bounce()> and M<forward()> is the reason
for message processing.  The I<bounce> has no intention to modify the
content of message: the same information is passed-on to someplace else.
This may mean some conversions, but for instance, the Message-ID does
not need to be changed.

The purpose of I<forward()> is to pass on information which is
modified: annotated or reduced.  The information is not sent back
to the author of the original message (which is implemented by M<reply()>),
but to someone else.

So: some information comes in, is modified, and than forwarded to someone
else.  Currently, there are four ways to get the original information
included, which are explained in the next sections.

After the creation of the forward, you may want to M<rebuild()> the
message to remove unnecessary complexities.  Of course, that is not
required.

=subsection forward, specify a body

When you specify M<forward(body)>, you have created your own body object to
be used as content of the forwarded message.  This implies that
M<forward(include)> is C<'NO'>: no automatic generation of the forwarded
body.

=subsection forward, inline the original

The M<forward(include)> is set to C<'INLINE'> (the default)
This is the most complicated situation, but most often used by MUAs:
the original message is inserted textually in the new body.  You can
set-up automatic stripping of signatures, the way of encapsulation,
and texts which should be added before and after the encapsulated part.

However, the result may not always be what you expect.  For instance,
some people use very long signatures which will not be automatically
stripped because the pass the threshold.  So, you probably need some
manual intervention after the message is created and before it is sent.

When a binary message is encountered, inlining is impossible.  In that
case, the message is treated as if C<'ENCAPSULATE'> was requested.

=subsection forward, attach the original

When M<forward(include)> is explicitly set to C<'ATTACH'> the result
will be a multipart which contains two parts.  The first part will
be your message, and the second the body of the original message.

This means that the headers of the forwarded message are used for
the new message, and detached from the part which now contains the
original body information.  Content related headers will (of course)
still be part of that part, but lines line C<To> and C<Subject> will
not be stored with that part.

As example of the structural transformation:

 # code: $original->printStructure;
 multipart/alternative: The source message
   text/plain: content in raw text
   text/html: content as html

 # code: $fwd = $original->forward(include => 'ATTACH');
 # code: $fwd->printStructure
 multipart/mixed: The source message
   text/plain: prelude/postlude/signature
   multipart/alternative
     text/plain: content in raw text
     text/html: content as html

=subsection forward, encapsulate the original

When M<forward(include)> is explicitly set to C<'ENCAPSULATE'>, then
the original message is left in-tact as good as possible.  The lines
of the original message are used in the main message header but also
enclosed in the part header.

The encapsulation is implemented using a nested message, content type
C<message/rfc822>.  As example of the structural transformation:

 # code: $original->printStructure;
 multipart/alternative: The source message
   text/plain: content in raw text
   text/html: content as html

 # code: $fwd = $original->forward(include => 'ENCAPSULATE');
 # code: $fwd->printStructure
 multipart/mixed: The source message
   text/plain: prelude/postlude/signature
   message/rfc822
      multipart/alternative: The source message
         text/plain: content in raw text
         text/html: content as html

The message structure is much more complex, but no information is lost.
This is probably the reason why many MUAs use this when the forward
an original message as attachment.

=cut

#------------------------------------------
 
1;
