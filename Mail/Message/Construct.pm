
use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';
use IO::Lines;

=head1 NAME

Mail::Message::Construct - extends the functionality of a Mail::Message

=head1 SYNOPSIS

 my $msg1 = Mail::Message->read(\*STDIN);
 my $msg2 = Mail::Message->read(\@lines);

 my $msg3 = Mail::Message->build
   (From => 'me', data => "only two\nlines\n");

 my $msg4 = Mail::Message->buildFromBody($body);

 my Mail::Message $reply = $message->reply;
 my $quoted  = $message->replyPrelude($head->get('From'));

=head1 DESCRIPTION

Read C<Mail::Box-Overview> and C<Mail::Message> first.

When complex methods are called on a C<Mail::Message>-object, this package
is autoloaded to supply that functionality.

=head1 METHODS

=cut

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=c_method read FILEHANDLE|SCALAR|REF-SCALAR|ARRAY-OF-LINES, OPTIONS

Read a message from a FILEHANDLE, SCALAR, a reference to a SCALAR, or
a reference to an array of LINES.  The OPTIONS are passed to the C<new()>
of the message which is created.

Please have a look at build() and buildFromBody()
before thinking about this C<read> method.
Use this C<read> only when you have a file-handle like STDIN to parse
from, or some external source of message lines.  When you already have a
separate set of head and body lines, then C<read> is certainly B<not>
your best choice.

=examples

 my $msg1 = Mail::Message->read(\*STDIN);
 my $msg2 = Mail::Message->read(\@lines, log => 'PROGRESS');
 $folder->addMessages($msg1, $msg2);

 my $msg3 = Mail::Message->read(<<MSG);
 Subject: hello world
 To: you@example.com
                      # warning: empty line required !!!
 Hi, greetings!
 MSG

=cut

sub read($@)
{   my ($class, $from) = (shift, shift);
    my ($filename, $file);
    my $ref       = ref $from;

    require IO::Scalar;

    if(!$ref)
    {   $filename = 'scalar';
        $file     = IO::Scalar->new(\$from);
    }
    elsif($ref eq 'SCALAR')
    {   $filename = 'ref scalar';
        $file     = IO::Scalar->new($from);
    }
    elsif($ref eq 'ARRAY')
    {   $filename = 'array of lines';
        my $buffer= join '', @$from;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        local $/;
        my $buffer= <$from>;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        my $buffer= join '', $from->getlines;
        $file     = IO::Scalar->new(\$buffer);
    }
    else
    {   croak "Cannot read from $from";
    }

    require Mail::Box::Parser::Perl;  # not parseable by C parser
    my $parser = Mail::Box::Parser::Perl->new
     ( filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $self = $class->new(@_);
    $self->readFromParser($parser);
    $parser->stop;

    my $head = $self->head;
    $head->set('Message-ID' => $self->messageId)
        unless $head->get('Message-ID');

    $self->statusToLabels;
    $self;
}

#------------------------------------------

=method reply OPTIONS

Start a reply to this message.  Some of the header-lines of the original
message will be taken.  A message-id will be assigned.  Some header lines
will be updated to facilitate message-thread detection
(see Mail::Box::Thread::Manager).

You may reply to a whole message or a message part.
You may wish to overrule some of the default header settings for the
reply immediately, or you may do that later with C<set> on the header.

ADDRESSES may be specified as string, or
a Mail::Address object, or as array of Mail::Address objects.

=option  body BODY
=default body undef

Usually, the reply method can create a nice, sufficient message from the
source message's body.  In case you like more complicated reformatting,
you may also create a body yourself first, and pass this on to this
C<reply> method. Some of the other options to this method will be ingored
in this case.

=option  group_reply BOOLEAN
=default group_reply <true>

Will the people listed in the C<Cc> headers (those who received the
message where you reply to now) also receive this message as carbon
copy?

=option  include 'NO'|'INLINE'|'ATTACH'
=default include 'INLINE'

Must the message where this is a reply to be included in the message?
If 'NO' then not.  With 'INLINE' a reply body is composed. 'ATTACH'
will create a multi-part body, where the original message is added
after the specified body.  It is only possible to inline textual
messages, therefore binary or multipart messages will always be
enclosed as attachment.

=option  message_type CLASS
=default message_type 'Mail::Message'

Create a message with the requested type.  By default, it will be a
Mail::Message.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=option  max_signature INTEGER
=default max_signature 10

Passed to C<stripSignature> on the body as parameter C<max_lines>.  Only
effective for single-part messages.

=option  prelude BODY|LINES
=default prelude undef

The line(s) which will be added before the quoted reply lines.  If nothing
is specified, the result of the replyPrelude() method
is taken.  When C<undef> is specified, no prelude will be added.

=option  postlude BODY|LINES
=default postlude undef

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.  This should not include the signature, which has its
own option.  The signature will be added after the postlude when the
reply is INLINEd.

=option  quote CODE|STRING
=default quote '=E<gt> '

Mangle the lines of an C<INLINE>d reply with CODE, or by prepending a
STRING to each line.  The routine specified by CODE is called when the
line is in C<$_>.

By default, C<'E<gt> '> is added before each line.  Specify C<undef> to
disable quoting.  This option is processed after the body has been decoded.

=option  signature BODY|MESSAGE
=default signature undef

The signature to be added in case of a multi-part reply.  The mime-type
of the signature body should indicate this is a used as such.  However,
in INLINE mode, the body will be taken, a line containing C<'-- '> added
before it, and added behind the epilogue.

=option  strip_signature REGEXP|STRING|CODE
=default strip_signature qr/^--\s/

Remove the signature of the sender.  The value of this parameter is passed
to the body's C<stripSignature> method (see C<Mail::Message::Body>)
as C<pattern> unless the source text is not included.  The signature is
stripped from the message before quoting.

When a multipart body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=option  To ADDRESSES
=default To <sender in current>

The destination of your message.  By default taken from the C<Reply-To>
field in the source message.  If that field is not present, the C<Sender>
field is taken.  If that field is not present as well, the C<From> line
is scanned.  If they all fail, C<undef> is returned.

=option  From ADDRESSES
=default From <'to' in current>

Your identification, by default taken from the C<To> field of the
source message.

=option  Bcc ADDRESSES
=default Bcc undef

Receivers of blind carbon copies: their names will not be published to
other message receivers.

=option  Cc ADDRESSES
=default Cc <'cc' in current>

The carbon-copy receivers, by default a copy of the C<Cc> field of
the source message.

=option  Message-ID STRING
=default Message-ID <uniquely generated>

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=option  Subject STRING|CODE
=default Subject <see replySubject()>

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the C<replySubject> method (described below) is used.

=examples

  my $reply = $msg->reply
   ( prelude         => "No spam, please!\n\n"
   , postlude        => "\nGreetings\n"
   , strip_signature => 1
   , signature       => $my_pgp_key
   , group_reply     => 1
   );

=error Cannot include reply source as $include.

Unknown alternative for the C<include> option of reply().  Valid choices are
C<NO>, C<INLINE>, and C<ATTACH>.

=cut

# tests in t/55reply1r.t, demo in the examples/ directory

sub reply(@)
{   my ($self, %args) = @_;

    my $body   = $args{body};
    my $strip  = !exists $args{strip_signature} || $args{strip_signature};
    my $include  = $args{include}   || 'INLINE';

    if($include eq 'NO')
    {   # Throw away real body.
        $body    = (ref $self)->new
           (data => ["\n[The original message is not included]\n\n"])
               unless defined $args{body};
    }
    elsif($include eq 'INLINE' || $include eq 'ATTACH')
    {
        unless(defined $body)
        {   # text attachment
            $body = $self->body;
            $body = $body->part(0) if $body->isMultipart && $body->parts==1;
            $body = $body->nested  if $body->isNested;

            $body
             = $strip && ! $body->isMultipart && !$body->isBinary
             ? $body->decoded->stripSignature
                 ( pattern   => $args{strip_signature}
                 , max_lines => $args{max_signature}
                 )
             : $body->decoded;
        }

        if($include eq 'INLINE' && $body->isMultipart) { $include = 'ATTACH' }
        elsif($include eq 'INLINE' && $body->isBinary)
        {   $include = 'ATTACH';
            $body    = Mail::Message::Body::Multipart->new(parts => [$body]);
        }

        if($include eq 'INLINE')
        {   my $quote
              = defined $args{quote} ? $args{quote}
              : exists $args{quote}  ? undef
              :                        '> ';

            if(defined $quote)
            {   my $quoting = ref $quote ? $quote : sub {$quote . $_};
                $body = $body->foreachLine($quoting);
            }
        }
    }
    else
    {   $self->log(ERROR => "Cannot include reply source as $include.");
        return;
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
    unless(defined $to)
    {   my $reply = $mainhead->get('reply-to');
        $to       = [ $reply->addresses ] if defined $reply;
    }
    $to  ||= $self->sender || return;

    # Add Cc
    my $cc = $args{Cc};
    if(!defined $cc && $args{group_reply})
    {   my @cc = $self->cc;
        $cc    = [ $self->cc ] if @cc;
    }

    # Add Bcc
    my $bcc = $args{Bcc};

    # Create a subject
    my $subject = $args{Subject};
    if(!defined $subject) { $subject = $self->replySubject($subject) }
    elsif(ref $subject)   { $subject = $subject->($subject) }

    # Create a nice message-id
    my $msgid   = $args{'Message-ID'};
    $msgid      = "<$msgid>" if $msgid && $msgid !~ /^\s*\<.*\>\s*$/;

    # Thread information
    my $origid  = '<'.$self->messageId.'>';
    my $refs    = $mainhead->get('references');

    # Prelude
    my $prelude
      = defined $args{prelude} ? $args{prelude}
      : exists $args{prelude}  ? undef
      :                          [ $self->replyPrelude($to) ];

    $prelude     = Mail::Message::Body->new(data => $prelude)
        if defined $prelude && ! blessed $prelude;
 
    my $postlude = $args{postlude};
    $postlude    = Mail::Message::Body->new(data => $postlude)
        if defined $postlude && ! blessed $postlude;

    #
    # Create the message.
    #

    my $total;
    if($include eq 'NO') {$total = $body}
    elsif($include eq 'INLINE')
    {   my $signature = $args{signature};
        $signature = $signature->body
           if defined $signature && $signature->isa('Mail::Message');

        $total = $body->concatenate
          ( $prelude, $body, $postlude
          , (defined $signature ? "-- \n" : undef), $signature
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
      , From    => $from || 'Undisclosed senders:;'
      , To      => $to
      , Subject => $subject
      , 'In-Reply-To' => $origid
      , References    => ($refs ? "$origid $refs" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc  => $cc)  if $cc;
    $newhead->set(Bcc => $args{Bcc}) if $args{Bcc};

    # Ready

    $self->log(PROGRESS => 'Reply created from '.$origid);
    $self->label(replied => 1);
    $reply;
}

#------------------------------------------

=ci_method replySubject STRING

Create a subject for a message which is a reply for this one.  This routine
tries to count the level of reply in subject field, and transform it into
a standard form.  Please contribute improvements.

=examples

 subject                 --> Re: subject
 Re: subject             --> Re[2]: subject
 Re[X]: subject          --> Re[X+1]: subject
 subject (Re)            --> Re[2]: subject
 subject (Forw)          --> Re[2]: subject
 <blank>                 --> Re: your mail

=cut

# tests in t/35reply1rs.t

sub replySubject($)
{   my ($thing, $subject) = @_;
    $subject     = 'your mail' unless defined $subject && length $subject;
    my @subject  = split /\:/, $subject;
    my $re_count = 1;

    # Strip multiple Re's from the start.

    while(@subject)
    {   last if $subject[0] =~ /[A-QS-Za-qs-z][A-DF-Za-df-z]/;

        for(shift @subject)
        {   while( /\bRe(?:\[\s*(\d+)\s*\]|\b)/g )
            {   $re_count += defined $1 ? $1 : 1;
            }
        }
    }

    # Strip multiple Re's from the end.

    if(@subject)
    {   for($subject[-1])
        {   $re_count++ while s/\s*\(\s*(re|forw)\W*\)\s*$//i;
        }
    }

    # Create the new subject string.

    my $text = (join ':', @subject) || 'your mail';
    for($text)
    {  s/^\s+//;
       s/\s+$//;
    }

    $re_count==1 ? "Re: $text" : "Re[$re_count]: $text";
}

#------------------------------------------

=method replyPrelude [STRING|FIELD|ADDRESS]

Produces a list of lines (usually only one), which will preceded the
quoted body of the message.  STRING must comply to the RFC822 email
address specification, and is usually the content of a C<To> or C<From>
header line.  If a FIELD is specified, the field's body must be
compliant.  Without argument -or when the argument is C<undef>- a
slightly different line is produced.

An characteristic example of the output is

 On Thu Oct 13 04:54:34 1995, him@example.com wrote:

=cut

sub replyPrelude($)
{   my ($self, $who) = @_;
 
    my $user
     = !ref $who                         ? (Mail::Address->parse($who))[0]
     : $who->isa('Mail::Message::Field') ? ($who->addresses)[0]
     :                                     $who;

    my $from
     = ref $user && $user->isa('Mail::Address')
     ? ($user->name || $user->address || $user->format)
     : 'someone';

    my $time = gmtime $self->timestamp;
    "On $time, $from wrote:\n";
}

#------------------------------------------

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
=default include 'INLINE'

Must the message where this is a reply to be included in the message?
With 'INLINE' a forward body is composed. 'ATTACH' will create a multi-part
body, where the original message is added after the specified body.  It is
only possible to inline textual messages, therefore binary or multi-part
messages will always be enclosed as attachment.

=option  message_type CLASS
=default message_type 'Mail::Message'

Create a message with the requested type.  By default, it will be a
C<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=option  max_signature INTEGER
=default max_signature 10

Passed to C<stripSignature> on the body as parameter C<max_lines>.  Only
effective for single-part messages.

=option  prelude BODY
=default prelude undef

The line(s) which will be added before the quoted forwarded lines.  If nothing
is specified, the result of the forwardPrelude() method (as described
below) is used.  When C<undef> is specified, no prelude
will be added.

=option  postlude BODY
=default postlude undef

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.  This should not include the signature, which has its
own option.  The signature will be added after the postlude when the
forwarded message is INLINEd.

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
=default strip_signature qr/^--\s/

Remove the signature of the sender.  The value of this parameter is passed
to the body's C<stripSignature> method (see C<Mail::Message::Body>)
as C<pattern> unless the source text is not included.  The signature is
stripped from the message before quoting.

When a multi-part body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=option  To ADDRESSES
=default To <obligatory>

The destination of your message. Obligatory.  The ADDRESSES may be
specified as string, a C<Mail::Address> object, or as array of
C<Mail::Address> objects.

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
=default Subject <see forwardSubject>

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the forwardSubject() method is used.

=error Cannot include forward source as $include.

Unknown alternative for the C<include> option of forward().  Valid choices are
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

#------------------------------------------

=c_method build [MESSAGE|BODY], CONTENT

Simplified message object builder.  In case a MESSAGE is
specified, a new message is created with the same body to start with, but
new headers.  A BODY may be specified as well.  However, there are more
ways to add data simply.

The CONTENT is a list of key-value pairs and header field objects.
The keys which start with a capital are used as header-lines.  Lowercased
fields are used for other purposes as listed below.  Each field may be used
more than once.  If more than one C<data>, C<file>, and C<attach> is
specified, a multi-parted message is created.

This C<build> method will use buildFromBody() when the body object has
been constructed.  Together, they produce your message.

=option  data STRING|ARRAY-OF-LINES
=default data undef

The text for one part, specified as one STRING, or an ARRAY of lines.  Each
line, including the last, must be terminated by a newline.  This argument
is passed to the C<data> options of C<Mail::Message::Body::new()> to
construct one.

  data => [ "line 1\n", "line 2\n" ]     # array of lines
  data => <<'TEXT'                       # string
 line 1
 line 2
 TEXT

=option  file FILENAME|FILEHANDLE|IOHANDLE
=default file undef

Create a body where the data is read from the specified FILENAME,
FILEHANDLE, or object of type C<IO::Handle>.  Also this body is used
to create a C<Mail::Message::Body>.

 my $in = IO::File->new('/etc/passwd', 'r');

 file => 'picture.jpg'                   # filename
 file => \*MYINPUTFILE                   # file handle
 file => $in                             # IO::Handle

=option  files ARRAY-OF-FILE
=default files []

See option file, but then an array reference collection more of them.

=option  attach BODY|MESSAGE|ARRAY-OF-BODY
=default attach undef

One attachment to the message.  Each attachment can be full MESSAGE or a BODY.

 attach => $folder->message(3)->decoded  # body
 attach => $folder->message(3)           # message

=option  head HEAD
=default head undef

Start with a prepared header, otherwise one is created.

=examples

 my $msg = Mail::Message->build
  ( From   => 'me@home.nl'
  , To     => Mail::Address->new('your name', 'you@yourplace.aq')
  , Cc     => 'everyone@example.com'
  , $other_message->get('Bcc')

  , data   => [ "This is\n", "the first part of\n", "the message\n" ]
  , file   => 'myself.gif'
  , file   => 'you.jpg'
  , attach => $signature
  );

=cut

sub build(@)
{   my $class = shift;

    my @parts
      = ! ref $_[0] ? ()
      : $_[0]->isa('Mail::Message')       ? shift
      : $_[0]->isa('Mail::Message::Body') ? shift
      :               ();

    my ($head, @headerlines);
    while(@_)
    {   my $key = shift;
        if(ref $key && $key->isa('Mail::Message::Field'))
        {   push @headerlines, $key;
            next;
        }

        my $value = shift;
        if($key eq 'head')
        {   $head = $value }
        elsif($key eq 'data')
        {   push @parts, Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   push @parts, Mail::Message::Body->new(file => $value) }
        elsif($key eq 'files')
        {   push @parts, map {Mail::Message::Body->new(file => $_) } @$value }
        elsif($key eq 'attach')
        {   push @parts, ref $value eq 'ARRAY' ? @$value : $value }
        elsif($key =~ m/^[A-Z]/)
        {   push @headerlines, $key, $value }
        else
        {   croak "Skipped unknown key $key in build." } 
    }

    my $body
       = @parts==0 ? Mail::Message::Body::Lines->new()
       : @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    $class->buildFromBody($body, $head, @headerlines);
}

#------------------------------------------

=c_method buildFromBody BODY, [HEAD], HEADERS

Shape a message around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.
You may specify a HEAD object which is pre-initialized, or one is
created for you (also when HEAD is C<undef>).
Next to that, more HEADERS can be specified which are stored in that
header.

Header fields are added in order, and before the header lines as
defined by the body are taken.  They may be supplied as key-value
pairs or Mail::Message::Field objects.  In case of a key-value
pair, the field's name is to be used as key and the value is a
string, address (Mail::Address object), or array of addresses.

A C<Date>, C<Message-Id>, and C<MIME-Version> field are added unless
supplied.

=examples

 my $type = Mail::Message::Field->new('Content-Type', 'text/html'
   , 'charset="us-ascii"');

 my @to   = ( Mail::Address->new('Your name', 'you@example.com')
            , 'world@example.info'
            );

 my $msg  = Mail::Message->buildFromBody
   ( $body
   , From => 'me@example.nl'
   , To   => \@to
   , $type
   );

=cut

sub buildFromBody(@)
{   my ($class, $body) = (shift, shift);
    my @log     = $body->logSettings;

    my $head;
    if(ref $_[0] && $_[0]->isa('Mail::Message::Head')) { $head = shift }
    else
    {   shift unless defined $_[0];   # undef as head
        $head = Mail::Message::Head::Complete->new(@log);
    }

    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $message = $class->new
     ( head => $head
     , @log
     );

    $message->body($body);
    $message->statusToLabels;

    # be sure the mesasge-id is actually stored in the header.
    $head->add('Message-Id' => '<'.$message->messageId.'>')
        unless defined $head->get('message-id');

    $head->add(Date => Mail::Message::Field->toDate)
        unless defined $head->get('Date');

    $head->add('MIME-Version' => '1.0')  # required by rfc2045
        unless defined $head->get('MIME-Version');

    $message;
}

#------------------------------------------

=method bounce [RG-OBJECT|OPTIONS]

The program calling this method considers itself as an intermediate step
in the message delivery process; it therefore leaves a resent group
of header fields as trace.

When a message is received, the Mail Transfer Agent (MTA) adds a
C<Received> field to the header.  As OPTIONS, you may specify lines
which are added to the resent group of that received field.  C<Resent->
is prepended before the field-names automatically, unless already present.

You may also specify an instantiated Mail::Message::Head::ResentGroup (RG)
object.  See Mail::Message::Head::ResentGroup::new() for the available
options.  This is required if you want to add a new resent group: create
a new C<Received> line in the header as well.

If you are planning to change the body of a bounce message, don't!  Bounced
messages have the same message-id as the original message, and therefore
should have the same content (message-ids are universally unique).  If you
still insist, use Mail::Message::body().

=examples

 my $bounce = $folder->message(3)->bounce(To => 'you', Bcc => 'everyone');

 $bounce->send;
 $outbox->addMessage($bounce);

 my $rg     = Mail::Message::Head::ResentGroup->new(To => 'you',
    Received => 'from ... by ...');
 $msg->bounce($rg)->send;

=cut

sub bounce(@)
{   my $self   = shift;
    my $bounce = $self->clone;
    my $head   = $bounce->head;

    if(@_==1 && ref $_[0] && $_[0]->isa('Mail::Message::Head::ResentGroup' ))
    {    $head->addResentGroup(shift);
         return $bounce;
    }

    my @rgs    = $head->resentGroups;  # No groups yet, then require Received
    my $rg     = $rgs[0];

    if(defined $rg)
    {   $rg->delete;     # Remove group to re-add it later: others field order
        while(@_)        #  in header would be disturbed.
        {   my $field = shift;
            ref $field ? $rg->set($field) : $rg->set($field, shift);
        }
    }
    else
    {   $rg = Mail::Message::Head::ResentGroup->new(@_, head => $head);
    }
 
    #
    # Add some nice extra fields.
    #

    $rg->set(Date => Mail::Message::Field->toDate)
        unless defined $rg->date;

    unless(defined $rg->messageId)
    {   my $msgid = $head->createMessageId;
        $rg->set('Message-ID' => "<$msgid>");
    }

    $head->addResentGroup($rg);
    $bounce;
}

#------------------------------------------

#------------------------------------------

=head2 Access to the Message

=cut

#------------------------------------------

=method string

Returns the whole message as string.

=cut

sub string()
{   my $self = shift;
    $self->head->string . $self->body->string;
}

#------------------------------------------

=method lines

Returns the whole message as set of lines.  In LIST context, copies of the
lines are returned.  In SCALAR context, a reference to an array of lines
is returned.

=cut

sub lines()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    wantarray ? @lines : \@lines;
}

#------------------------------------------

=method file

Returns the message as file-handle.

=cut

sub file()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    $file->setpos(0,0);
    $file;
}

#------------------------------------------

=head2 Logging and Tracing

=cut

#------------------------------------------

=method printStructure [FILEHANDLE][, INDENT]

Print the structure of a message to the selected filehandle.
The message's subject and the types of all composing parts are
displayed.

INDENT specifies the initial indentation string: it is added in
front of each line, and SHALL end with a blank, if specified.

=examples

 my $msg = ...;
 $msg->printStructure(\*OUTPUT);
 $msg->printStructure;

 # Possible output for one message:
 multipart/mixed: forwarded message from Pietje Puk (1550 bytes)
    text/plain (164 bytes)
    message/rfc822 (1043 bytes)
       multipart/alternative: A multipart alternative (942 bytes)
          text/plain (148 bytes, deleted)
          text/html (358 bytes)

=cut

sub printStructure(;$$)
{   my $self    = shift;
    my $indent  = @_ && !ref $_[-1] && substr($_[-1], -1, 1) eq ' ' ? pop : '';
    my $fh      = @_ ? shift : select;

    my $subject = $self->get('Subject') || '';
    $subject    = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type') || '';
    my $size    = $self->size;
    my $deleted = $self->can('isDeleted') && $self->isDeleted ? ', deleted' : '';

    $fh->print("$indent$type$subject ($size bytes$deleted)\n");

    my $body    = $self->body;
    my @parts
      = $body->isMultipart ? $body->parts
      : $body->isNested    ? ($body->nested)
      :                      ();

    $_->printStructure($fh, $indent.'   ') foreach @parts;
}
    
1;
