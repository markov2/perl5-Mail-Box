
use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;

our $VERSION = 2.014;

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';

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

When complex methods are called on a C<Mail::Message>-object, this
package is autoloaded to supply that functionality.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Construct> objects:

      bounce OPTIONS                       forwardPrelude
      build [MESSAGE|BODY], CONTENT        forwardSubject STRING
      buildFromBody BODY, HEADERS          read FILEHANDLE|SCALAR|REF-...
      forward OPTIONS                      reply OPTIONS
      forwardPostlude                      replyPrelude [STRING|FIELD|...

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item read FILEHANDLE|SCALAR|REF-SCALAR|ARRAY-OF-LINES, OPTIONS

(Class method)
Read a message from a FILEHANDLE, SCALAR, a reference to a SCALAR, or
an array of LINES.  The OPTIONS are passed to the C<new()> of the message
which is created.

Please have a look at C<build> and C<buildFromBody> in
C<Mail::Message::Construct> before thinking about this C<read> method.
Use this C<read> only when you have a file-handle like STDIN to parse
from, or some external source of message lines.  When you already have a
separate set of head and body lines, then C<read> is certainly B<not>
your best choice.

Examples:

 my $msg1 = Mail::Message->read(\*STDIN);
 my $msg2 = Mail::Message->read(\@lines, log => 'PROGRESS');
 $folder->addMessages($msg1, $msg2);

 my $msg3 = Mail::Message->read(<<MSG);
 Subject: hello world
 To: you@example.com
                      # warning: empty line required !!!
 Hi, greatings!
 MSG

=cut

sub read($@)
{   my ($class, $from) = (shift, shift);
    my ($filename, $file);
    my $ref       = ref $from;

    require IO::Scalar;
    require IO::ScalarArray;

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
        $file     = IO::ScalarArray->new($from);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        $file     = IO::ScalarArray->new( [ <$from> ] );
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        $file     = IO::ScalarArray->new( [ $from->getlines ] );
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

    my $head = $self->head;
    $head->set('Message-ID' => $self->messageId)
        unless $head->get('Message-ID');

    $self;
}

#------------------------------------------

=item reply OPTIONS

Start a reply to this message.  Some of the header-lines of the original
message will be taken.  A message-id will be assigned.  Some header lines
will be updated to facilitate message-thread detection
(see C<Mail::Box::Thread::Manager>).

You may reply to a whole message or a message part.

 OPTIONS         DESCRIBED IN              DEFAULT
 Bcc             Mail::Message::Construct  undef
 Cc              Mail::Message::Construct  <'cc' in current>
 From            Mail::Message::Construct  <'to' in current>
 Message-ID      Mail::Message::Construct  <uniquely generated>
 Subject         Mail::Message::Construct  <see replySubject>
 To              Mail::Message::Construct  <'from' in current>

 body            Mail::Message::Construct  undef
 group_reply     Mail::Message::Construct  1
 include         Mail::Message::Construct  'INLINE'
 message_type    Mail::Message::Construct  'Mail::Message'
 postlude        Mail::Message::Construct  undef
 prelude         Mail::Message::Construct  undef
 quote           Mail::Message::Construct  '=E<gt> '
 strip_signature Mail::Message::Construct  qr/^--\s/

The OPTIONS are:

=over 4

=item * body =E<gt> BODY

Specifies the body of the message which is the reply.  Adviced in other
cases: prepare the body of the reply before the reply is called.  It will
avoid needless copying within C<Mail::Message>.

=item * group_reply =E<gt> BOOLEAN

Will the people listed in the C<Cc> headers (those who received the
message where you reply to now) also receive this message as carbon
copy?

=item * include =E<gt> 'NO'|'INLINE'|'ATTACH'

Must the message where this is a reply to be included in the message?
If 'NO' then not.  With 'INLINE' a reply body is composed. 'ATTACH'
will create a multi-part body, where the original message is added
after the specified body.  It is only possible to inline textual
messages, therefore binary or multipart messages will always be
inclosed as attachment.

=item * message_type =E<gt> CLASS

Create a message with the requested type.  By default, it will be a
C<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=item * max_signature =E<gt> INTEGER

Passed to C<stripSignature> on the body as parameter C<max_lines>.  Only
effective for single-part messages.

=item * prelude =E<gt> BODY|LINES

The line(s) which will be added before the quoted reply lines.  If nothing
is specified, the result of the C<replyPrelude()> method (as described below)
is taken.  When C<undef> is specified, no prelude will be added.

=item * postlude =E<gt> BODY|LINES

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.  This should not include the signature, which has its
own option.  The signature will be added after the postlude when the
reply is INLINEd.

=item * quote =E<gt> CODE|STRING

Mangle the lines of an C<INLINE>d reply with CODE, or by prepending a
STRING to each line.  The routine specified by CODE is called when the
line is in C<$_>.

By default, C<'E<gt> '> is added before each line.  Specify C<undef> to
disable quoting.  This option is processed after the body has been decoded.

=item * signature =E<gt> BODY|MESSAGE

The signature to be added in case of a multi-part reply.  The mime-type
of the signature body should indicate this is a used as such.  However,
in INLINE mode, the body will be taken, a line containing C<'-- '> added
before it, and added behind the epilogue.

=item * strip_signature =E<gt> REGEXP|STRING|CODE

Remove the signature of the sender.  The value of this paramter is passed
to the body's C<stripSignature> method (see C<Mail::Message::Body>)
as C<pattern> unless the source text is not included.  The signature is
stripped from the message before quoting.

When a multipart body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=back

You may wish to overrule some of the default settings for the
reply immediately (or you may do later with C<set()> on the header).
To overrule use

=over 4

=item * To =E<gt> ADDRESSES

The destination of your message, by default taken from the C<Reply-To>
field in the source message.  If that field is not present, the C<From> field
is taken.  The ADDRESSES may be specified as string, or
a C<Mail::Address> object, or as array of C<Mail::Address> objects.

=item * From =E<gt> ADDRESSEj

Your identification, by default taken from the C<To> field of the
source message.

=item * Bcc =E<gt> ADDRESSES

Receivers of blind carbon copies: their names will not be published to
other message receivers.

=item * Cc =E<gt> ADDRESSES

The carbon-copy receivers, by default a copy of the C<Cc> field of
the source message.

=item * Message-ID =E<gt> STRING

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=item * Subject =E<gt> STRING|CODE

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the C<replySubject> method (described below) is used.

=back

Example:

  my $reply = $msg->reply
   ( prelude         => "No spam, please!\n\n"
   , postlude        => "\nGreetings\n"
   , strip_signature => 1
   , signature       => $my_pgp_key
   , group_reply     => 1
   );

=cut

# tests in t/55reply1r.t, demo in the examples/ directory

sub reply(@)
{   my ($self, %args) = @_;

    my $include  = $args{include}   || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    if($include eq 'NO')
    {   # Throw away real body.
        $body    = (ref $self)->new
           (data => ["\n[The original message is not included]\n\n"])
               unless defined $args{body};
    }
    elsif($include eq 'INLINE' || $include eq 'ATTACH')
    {   my @stripopts =
         ( pattern     => $args{strip_signature}
         , max_lines   => $args{max_signature}
         );

        my $decoded  = $body->decoded;
        $body        = $strip ? $decoded->stripSignature(@stripopts) : $decoded;

        if($body->isMultipart && $body->parts==1)
        {   $decoded = $body->part(0)->decoded;
            $body    = $strip ? $decoded->stripSignature(@stripopts) : $decoded;
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
    {   $self->log(ERROR => "Cannot include source as $include.");
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
    $to  ||= $self->from || return;

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
      , From    => $from || '(undisclosed)'
      , To      => $to
      , Subject => $subject
      , 'In-Reply-To' => $origid
      , References    => ($refs ? "$origid $refs" : $origid)
      );

    my $newhead = $reply->head;
    $newhead->set(Cc  => $cc)  if $cc;
    $newhead->set(Bcc => $args{Bcc}) if $args{Bcc};
    $newhead->set('Message-ID'  => $msgid || $newhead->createMessageId);

    # Ready

    $self->log(PROGRESS => 'Reply created from '.$origid);
    $self->label(replied => 1);
    $reply;
}

#------------------------------------------

=item replySubject STRING

(Class or Instance method)
Create a subject for a message which is a reply for this one.  This routine
tries to count the level of reply in subject field, and transform it into
a standard form.  Please contribute improvements.

  subject                 --> Re: subject
  Re: subject             --> Re[2]: subject
  Re[X]: subject          --> Re[X+1]: subject
  subject (Re)            --> Re[2]: subject
  subject (Forw)          --> Re[2]: subject
                          --> Re: your mail

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

=item replyPrelude [STRING|FIELD|ADDRESS]

Produces a list of lines (usually only one), which will preceed the
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

    my $from      = ref $user && $user->isa('Mail::Address')
     ? $user->name : 'someone';

    my $time      = gmtime $self->timestamp;
    "On $time, $from wrote:\n";
}

#------------------------------------------

=item forward OPTIONS

Forward the content of this message.  The body of the message to be forwarded
is encapsulated in some accompanying text (if you have no wish for that, than
C<bounce> is your choice).

You may forward a whole message, but also message parts.

 OPTIONS         DESCRIBED IN              DEFAULT
 Bcc             Mail::Message::Construct  undef
 Cc              Mail::Message::Construct  undef
 From            Mail::Message::Construct  <'to' in current>
 Message-ID      Mail::Message::Construct  <uniquely generated>
 Subject         Mail::Message::Construct  <see forwardSubject>
 To              Mail::Message::Construct  <obligatory>

 body            Mail::Message::Construct  undef
 include         Mail::Message::Construct  'INLINE'
 message_type    Mail::Message::Construct  'Mail::Message'
 postlude        Mail::Message::Construct  undef
 prelude         Mail::Message::Construct  undef
 quote           Mail::Message::Construct  undef
 strip_signature Mail::Message::Construct  qr/^--\s/

The OPTIONS are:

=over 4

=item * include =E<gt> 'INLINE'|'ATTACH'

Must the message where this is a reply to be included in the message?
With 'INLINE' a forward body is composed. 'ATTACH' will create a multi-part
body, where the original message is added after the specified body.  It is
only possible to inline textual messages, therefore binary or multi-part
messages will always be inclosed as attachment.

=item * message_type =E<gt> CLASS

Create a message with the requested type.  By default, it will be a
C<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=item * max_signature =E<gt> INTEGER

Passed to C<stripSignature> on the body as parameter C<max_lines>.  Only
effective for single-part messages.

=item * prelude =E<gt> BODY

The line(s) which will be added before the quoted forwarded lines.  If nothing
is specified, the result of the C<forwardPrelude()> method (as described
below) is used.  When C<undef> is specified, no prelude
will be added.

=item * postlude =E<gt> BODY

The line(s) which to be added after the quoted reply lines.  Create a
body for it first.  This should not include the signature, which has its
own option.  The signature will be added after the postlude when the
forwarded message is INLINEd.

=item * quote =E<gt> CODE|STRING

Mangle the lines of an C<INLINE>d reply with CODE, or by prepending a
STRING to each line.  The routine specified by CODE is called when the
line is in C<$_>.

By default, nothing is added before each line.  This option is processed
after the body has been decoded.

=item * signature =E<gt> BODY|MESSAGE

The signature to be added in case of a multi-part forward.  The mime-type
of the signature body should indicate this is a used as such.  However,
in INLINE mode, the body will be taken, a line containing C<'-- '> added
before it, and added behind the epilogue.

=item * strip_signature =E<gt> REGEXP|STRING|CODE

Remove the signature of the sender.  The value of this paramter is passed
to the body's C<stripSignature> method (see C<Mail::Message::Body>)
as C<pattern> unless the source text is not included.  The signature is
stripped from the message before quoting.

When a multi-part body is encountered, and the message is included to
ATTACH, the parts which look like signatures will be removed.  If only
one message remains, it will be the added as single attachment, otherwise
a nested multipart will be the result.  The value of this option does not
matter, as long as it is present.  See C<Mail::Message::Body::Multipart>.

=back

You may wish to overrule some of the default settings for the
reply immediately (or you may do later with C<set()> on the header).
To overrule use

=over 4

=item * To =E<gt> ADDRESSES

The destination of your message. Obligatory.  The ADDRESSES may be
specified as string, a C<Mail::Address> object, or as array of
C<Mail::Address> objects.

=item * From =E<gt> ADDRESSES

Your identification, by default taken from the C<To> field of the
source message.

=item * Bcc =E<gt> ADDRESSES

Receivers of blind carbon copies: their names will not be published to
other message receivers.

=item * Cc =E<gt> ADDRESSES

The carbon-copy receivers, by default noone.

=item * Date =E<gt> DATE

The date to be used in the message sent.

=item * Message-ID =E<gt> STRING

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=item * Subject =E<gt> STRING|CODE

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the C<forwardSubject> method (described below) is used.

=back

=cut

# tests in t/57forw1f.t

sub forward(@)
{   my ($self, %args) = @_;

    my $include  = $args{include} || 'INLINE';
    my $strip    = !exists $args{strip_signature} || $args{strip_signature};
    my $body     = defined $args{body} ? $args{body} : $self->body;

    unless($include eq 'INLINE' || $include eq 'ATTACH')
    {   $self->log(ERROR => "Cannot include source as $include.");
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
    my $to = $args{To}
      or croak "No address to forwarded to";

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
    $newhead->set('Message-ID' => $msgid || $newhead->createMessageId);

    # Ready

    $self->log(PROGRESS => 'Forward created from '.$origid);
    $reply;
}

#------------------------------------------

=item forwardSubject STRING

Create a subject for a message which is a forward from this one.  This routine
tries to count the level of reply in subject field, and transform it into
a standard form.  Please contribute improvements.

  subject                 --> Forw: subject
  Re: subject             --> Forw: Re: subject
  Re[X]: subject          --> Forw: Re[X]: subject
                          --> Forwarded

=cut

# tests in t/57forw0s.t

sub forwardSubject($)
{   my ($self, $subject) = @_;
    defined $subject && length $subject ? "Forw: $subject" : "Forwarded";
}

#------------------------------------------

=item forwardPrelude

Create a few lines to be included before the forwarded message
content.  The return is an array of lines. Some example output is:

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
    my $r     = $head->isResent ? 'resent-' : '';
    my $from  = $head->get($r.'from');
    my $to    = $head->get($r.'to');
    my $cc    = $head->get($r.'cc');
    my $date  = $head->get($r.'date');

    push @lines, $from->toString if defined $from;
    push @lines,   $to->toString if defined $to;
    push @lines,   $cc->toString if defined $cc;
    push @lines, $date->toString if defined $date;
    push @lines, "\n";

    \@lines;
}

#------------------------------------------

=item forwardPostlude

Added after the forwarded message.  The output is:

 ---- END forwarded message

=cut

sub forwardPostlude()
{   my $self = shift;
    my @lines = ("---- END forwarded message\n");
    \@lines;
}

#------------------------------------------

=item build [MESSAGE|BODY], CONTENT

(Class method) Simplified message object builder.  In case a MESSAGE is
specified, a new message is created with the same body to start with, but
new headers.  A BODY may be specified as well.  However, there are more
ways to add data simply.

The CONTENT is a list of key-value pairs.  The keys which start with a
capital are used as header-lines.  Lowercased fields are used for other
purposes as listed below.  Each field may be used more than once.

When the CONTENT reflects a header field to be, the key is used as
name of the field (be careful with the capitisation).  The value
can be a string, an address (C<Mail::Address> object), or a reference
to an array of addresses.

Special purpose keys (all other are header lines):

=over 4

=item data =E<gt> STRING|ARRAY-OF-LINES

The text for one part, specified as one STRING, or an ARRAY of lines.  Each
line, including the last, must be terminated by a newline.  This argument
is passed to the C<data> options of C<Mail::Message::Body::new()> to
construct one.

  data => [ "line 1\n", "line 2\n" ]     # array of lines
  data => <<'TEXT'                       # string
 line 1
 line 2
 TEXT

=item file =E<gt> FILENAME|FILEHANDLE|IOHANDLE

Create a body where the data is read from the specified FILENAME,
FILEHANDLE, or object of type C<IO::Handle>.  Also this body is used
to create a C<Mail::Message::Body>.

 my $in = IO::File->new('/etc/passwd', 'r');

 file => 'picture.jpg'                   # filename
 file => \*MYINPUTFILE                   # file handle
 file => $in                             # IO::Handle

=item attach =E<gt> BODY|MESSAGE|ARRAY-OF-BODY

One ATTACHMENT to the message.  Each ATTACHMENT can be full message or a body.

 attach => $folder->message(3)->decoded  # body
 attach => $folder->message(3)           # message

=back

If more than one C<data>, C<file>, and C<attach> is specified, a
multi-parted message is created.

Example:

 my $msg = Mail::Message->build
  ( From   => 'me@home.nl'
  , To     => Mail::Address->new('your name', 'you@yourplace.aq')
  , Cc     => 'everyone@example.com'

  , data   => [ "This is\n", "the first part of\n", "the message\n" ]
  , file   => 'myself.gif'
  , file   => 'you.jpg'
  , attach => $signature
  );

=cut

sub build(@)
{   my $class = shift;

    my $head  = Mail::Message::Head::Complete->new;
    my @parts = @_ % 2 ? shift : ();
    
    while(@_)
    {   my ($key, $value) = (shift, shift);
        if($key eq 'data')
        {   push @parts, Mail::Message::Body->new(data => $value) }
        elsif($key eq 'file')
        {   push @parts, Mail::Message::Body->new(file => $value) }
        elsif($key eq 'attach')
        {   push @parts, ref $value eq 'ARRAY' ? @$value : $value }
        elsif($key =~ m/^[A-Z]/)
        {   $head->add($key => $value) }
        else
        {   croak "Skipped unknown key $key in build." } 
    }

    my $message = $class->new(head => $head);
    my $body    = @parts==1 ? $parts[0]
       : Mail::Message::Body::Multipart->new(parts => \@parts);

    $message->body($body->check);
    $message->statusToLabels;

    $message;
}

#------------------------------------------

=item buildFromBody BODY, HEADERS

(Class method)
Shape a message around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.
Next to that, more HEADERS can be specified.

Header fields are added in order, and before the header lines as
defined by the body are taken.  They may be spullied as key-value
pairs or C<Mail::Message::Field> objects.  In case of a key-value
pair, the field's name is to be used as key and the value is a
string, address (C<Mail::Address> object), or array of addresses.

The C<To> and C<From> fields must be specified.  A C<Date> field is
added unless supplied.

Example:

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

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    carp "From and To fields are obligatory"
        unless defined $head->get('From') && defined $head->get('To');

    $head->set(Date => Mail::Message::Field->toDate(localtime))
        unless defined $head->get('Date');

    my $message = $class->new
     ( head => $head
     , @log
     );

    $message->body($body->check);
    $message->statusToLabels;
    $message;
}

#------------------------------------------

=item bounce OPTIONS

Bounce the message off to a difference destination, or multiple
destinations.  Most OPTIONS specify header lines which are added
to the original message.  Their name will therefor be prepended by
C<Resent->.  These lines have preference over the lines which do
not start with C<Resent->.

Possible OPTIONS are

=over 4

=item * From =E<gt> ADDRESS

Your address as string or C<Mail::Address> object.

=item * To =E<gt> ADDRESSES

One or more destination addresses, as string, one C<Mail::Address> object or
array of C<Mail::Address> objects.

=item * Cc =E<gt> ADDRESSES

The receiver(s) of carbon-copies: not the main targets, but receiving
an informational copy.

=item * Bcc =E<gt> ADDRESSES

The receiver(s) of blind carbon-copies: the other receivers will not
see these addresses.

=item * Date =E<gt> STRING

A properly formatted STRING for the date.  If not specified, the current
time is used.

=item * 'Message-ID' =E<gt> KEY

A unique KEY which identifies this message.  If you do not specify a key,
one is chosen for you.  There is one C<Resent-Message-ID> which identifies
all bounces for this message.  If one id is already present, than this
option will be ignored.

=item * 'Reply-To' =E<gt> ADDRESS

The address where the receiver has to reply to.

=back

Examples:

 my $bounce = $folder->message(3)->bounce(To => 'you', Bcc => 'everyone');
 $bounce->send;
 $outbox->addMessage($bounce);

=cut

sub bounce(@)
{   my ($self, %args) = @_;

    my $bounce = $self->clone;
    my $head   = $bounce->head;

    my $date   = $args{Date} || Mail::Message::Field->toDate(localtime);

    $head->add('Resent-From' => $args{From}) if $args{From};
    $head->add('Resent-To'   => $args{To}  ) if $args{To};
    $head->add('Resent-Cc'   => $args{Cc}  ) if $args{Cc};
    $head->add('Resent-Bcc'  => $args{Bcc} ) if $args{Bcc};
    $head->add('Resent-Date' => $date);
    $head->add('Resent-Reply-To' => $args{'Reply-To'}) if $args{'Reply-To'};

    unless(defined $head->get('Resent-Message-ID'))
    {   my $msgid  = $args{'Message-ID'} || $head->createMessageId;
        $msgid = "<$msgid>" unless $msgid =~ m/\<.*\>/;
        $head->add('Resent-Message-ID' => $msgid);
    }

    $bounce;
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.014.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
