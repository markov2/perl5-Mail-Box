
use strict;

# file Mail::Message::Construct extends functionalities from Mail::Message

package Mail::Message;

our $VERSION = '2.00_10';

use Mail::Address;
use Carp;

=head1 NAME

 Mail::Message::Construct - Extends the functionality of a Mail::Message

=head1 SYNOPSIS

 my Mail::Message $message = $folder->message(4);
 my Mail::Message $reply   = $message->reply;
 $message->body2multipart;

=head1 DESCRIPTION

Read C<Mail::Box::Manager> and C<Mail::Message> first.

When complex methods are called on a C<Mail::Message>-object, this
package is autoloaded to supply that functionality.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Construct> objects:

      body2multipart OPTIONS               reply OPTIONS
      build OPTIONS                        replySubject STRING
      quotePrelude [STRING|FIELD]          stripSignature [LINES|BODY,...

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item stripSignature [LINES|BODY,] OPTIONS

(Class or instance method)
Strip the signature from the specified LINES (passed as reference to an
array) or BODY.  If none of both is specified, then the body of the
message is taken.

The Signature is added by the sender to tell about him-
or herself.  It is superfluous in some situations, for instance if you
want to create a reply to the person's message you do not need to include
that signature.

The array or body which are specified as first argument are modified.  The
lines of the signature are returned as ref-array.  The first line of this
array is the separator.

The OPTIONS are

=over 4

=item * pattern =E<gt> REGEX|STRING|CODE

Which pattern defines the line which indicates the separator between
the message and the signature.  In case of a STRING, this is matched
to the beginning of the line, and REGEX is a full regular expression.

In case of CODE, each line (from last to front) is passed to the
specified subroutine as first argument.  The subroutine must return
TRUE when the separator is found.

By default, the scan is for C<"-- ">.

=item * max_lines =E<gt> INTERGER

The maximum number of lines which can be the length of a signature, which
defaults to 10.

=back

Examples:

   my @lines = ('a', 'b', '--', 'sig');
   my $sig   = Mail::Message->stripSignature(\@lines);
     # now @lines==('a', 'b') and $sig==['--', 'sig']

   my Mail::Message $msg;
   my Mail::Message::Body $body;

   my $sig   = Mail::Message->stripSignature($body); 
   my $sig   = $body->stripSignature;  # equivalent
   my $sig   = $msg->stripSignature;   # equivalent

   # non-destructive to body
   my $lines = $body->lines;
   my $sig   = Mail::Message->stripSignature($lines);

=cut

# tests in t/35reply0s.t

sub stripSignature($@)
{   my $self    = shift;
    my $source  = @_ && ref $_[0] ? shift : $self->body;
    my %args    = @_;

    my $lines   = ref $source eq 'ARRAY' ? $source : $source->lines;

    my $pattern = !defined $args{pattern} ? qr/^--(\s|$)/
                : !ref $args{pattern}     ? qr/^${args{pattern}}/
                :                           $args{pattern};
 
    my $stop = @$lines - ($args{max_lines} || 10);
    $stop = 0 if $stop < 0;
    my ($sigstart, $found);
 
    if(ref $pattern eq 'CODE')
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $pattern->($lines->[$sigstart]);
            $found = 1;
            last;
        }
    }
    else
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $lines->[$sigstart] =~ $pattern;
            $found = 1;
            last;
        }
    }
 
    return [] unless $found;
 
    my $sig  = [ splice @$lines, $sigstart ];
    $source->data($lines) if ref $source ne 'ARRAY';  #body
    $sig;
}

#------------------------------------------

=item reply OPTIONS

Start a reply to this message.  Some of the header-lines of the original
message will be taken.  A message-id will be assigned.  Some header lines
will be updated to facilitate message-thread detection
(see C<Mail::Box::Thread::Manager>).

In case you C<reply> on a multipart message, it will answer on the first
message-part.  You may also reply explicitly on a single message-part.

The OPTIONS are:

=over 4

=item * message_id =E<gt> STRING

Supply a STRING as specific message-id for the reply.  By default, one is
generated for you.  If there are no angles around your id, they will be
added.

=item * subject =E<gt> STRING|CODE

Force the subject line to the specific STRING, or the result of the
subroutine specified by CODE.  The subroutine will be called passing
the subject of the original message as only argument.  By default,
the C<replySubject> method (described below) is used.

=item * head =E<gt> HEAD

Specify an explicit HEAD-object to be used to start with.  Some fields
will be changed or added.  HEAD must be a C<Mail::Message::Head>.

=item * body =E<gt> BODY

Specify the reply's body immediately.  This BODY must be a
C<Mail::Message::Body>.  It can also be added later.

=item * copy_body =E<gt> BOOLEAN

Create a copy of the originating body.  Default is TRUE.

=item group_reply =E<gt> BOOLEAN

Will the C<CC> headers be copied too?

=item * message_type =E<gt> CLASS

Create a message with the requested type.  By default, it will be a
C<Mail::Message>.  This is correct, because it will be coerced into
the correct folder message type when it is added to that folder.

=back

You may which to overrule some of the default settings for the
reply immediately (or you may do later with C<set()> on the header).
To overrule use

=over 4

=item * to =E<gt> STRING

The destination of your message, by default taken from the C<From> field
of the source message.

=item * from =E<gt> STRING

Your identification, by default taken from the C<To> field of the
source message.

=item * cc =E<gt> STRING

The carbon-copy receivers, by default a copy of the C<Cc> field of
the source message.

=back

If C<copy_body> is TRUE (the default) or a C<body> is specified,
the following options apply.

=over 4

=item * body_type =E<gt> CLASS

Specifies the type of the body to be created.
The body-type of the produced will be the same as that of the original,
unless the C<body_type> option says different.

It is currently not possible to create multipart replies with this method.

=item * prelude =E<gt> STRING|ARRAY-OF-STRINGS

The line(s) which will be added before the quoted reply lines.  If nothing
is specified, the result of the C<replyPrelude()> method (as described below)
is taken.  When C<undef> is specified, no prelude will be added.  In case
of only one STRING, it will be split into lines first.

=item * postlude =E<gt> STRINGS|ARRAY-OF-STRINGS

The line(s) which to be added after the quoted reply lines.  In case
of only one STRING, it will be split into lines first.  The default is
no postlude.

=item * quote =E<gt> STRING|CODE

Copy the content of the original message into a body for the new message,
prepending the STRING for each line.  The default string is C<'E<gt> '>.
Specify C<undef> to disable quoting.

In case of CODE, each line is passed as first argument to the specified
subroutine and the result is included in the new body.  If the routine
returns C<undef>, the line is skipped.

=item * strip_signature =E<gt> REGEXP|STRING|CODE

Do not take the separator in the copy of the body.  The REGEXP, STRING, or
CODE is passed to the C<stripSeparator> method.  The STRING with be matched on
the start of the line.  If set to C<undef>, the
signature will not be stripped, however C<^--\s> is the default here.

=back

=cut

# tests in t/35reply2m.t

sub reply(@)
{   my ($self, %args) = @_;

    my $body      = $self->body;
    my $copy_body = exists $args{copy_body} ? $args{copy_body} : 1;

    return $body->part(0)->reply(%args)
       if $copy_body && $body->isMultipart;

    my $mainhead  = $self->toplevel->head;

    #
    # Create the header.
    # Basic header with some copied lines from the main message-header,
    # and some from this part.

    my $newhead = Mail::Message::Head::Complete->new;

    # Me, but with the alias which is known by the user.
    my $from;
    unless($from = $args{from})
    {   $from = $mainhead->get('To');
        $from = $from->body if $from;
    }
    $newhead->add(From => $from || '(undisclosed)');

    # To whom to send
    my $to;
    unless($to = $args{to})
    {   $to = $mainhead->get('reply-to') || $mainhead->get('from')
              || $mainhead->get('sender');
        $to = $to->body if $to;
    }
    return undef unless $to;
    $newhead->add(To => $to);

    # Add CC
    my $cc;
    if(!($cc = $args{cc}) && $args{group_reply})
    {   $cc = $mainhead->get('cc');
        $cc = $cc->body if $cc;
    }
    $newhead->add(Cc => $cc) if $cc;

    # Create a subject
    my $subject;
    if(exists $args{subject} && ! ref $args{subject})
    {   $subject       = $args{subject};
    }
    else
    {   my $rawsubject = $mainhead->get('subject')->body || 'your mail';
        my $make       = $args{subject} || \&replySubject;
        $subject       = $make->($rawsubject);
    }

    $newhead->add(Subject => $subject);

    # Create a nice message-id
    my $msgid   = $args{message_id} || $newhead->createMessageId;
    $msgid      = "<$msgid>" unless $msgid =~ /^\s*\<.*\>\s*$/;
    $newhead->add('Message-Id' => $msgid);

    # Add thread information
    my $origid  = $self->messageId;
    $newhead->set('In-Reply-To' => $origid);
    my $refs    = $mainhead->get('references');
    $newhead->set(References    => ($refs ? "$origid $refs" : $origid));

    #
    # Create the body
    #

    my $newbody;
    if($args{body})
    {   $newbody      = $args{body};
    }
    elsif($copy_body)
    {   my $parthead  = $self->head;
        my @patterns  = qw/Content- Lines Status X-Status/;
        foreach my $name ($parthead->grepNames(@patterns))
        {   $newhead->add($_->clone) foreach $parthead->get($name);
        }

        my $body_type = $args{body_type} || ref $body;

        $newbody      = $body_type->new;

        my $strip
          = exists $args{strip_signature} ? $args{strip_signature}
          :                                 qr/^--(\s|$)/;

        my @lines     = $body->lines;

        $self->stripSignature(\@lines, pattern => $strip)
            if defined $strip;

        my $quote = exists $args{quote} ? $args{quote} : '> ';
        my @newlines
          = !defined $quote ? @lines
          : ref $quote      ? grep {defined $_} map {$quote->($_)} @lines
          :                   map { "$quote$_" } @lines;

        if(exists $args{prelude})
        {   my $pre     = $args{prelude} || [];
            my @prelude = ref $pre ? @$pre : split /(?<=\n)/, $pre;
            unshift @newlines, @prelude;
        }
        else
        {   unshift @newlines, $self->quotePrelude($to);
        }

        if(my $post = $args{postlude})
        {   my @postlude = ref $post ? @$post : split /(?<=\n)/, $post;
            push @newlines, @postlude;
        }

        $newbody->data(\@newlines);
    }

    #
    # Now construct the message
    #

    my $msgtype = $args{message_type} || 'Mail::Message';
    my $message = $msgtype->new
     ( head  => $newhead
     , body  => $newbody
     , $self->logSettings
     );

    $self->log(PROGRESS => 'Reply created from '.$origid);

    $message;
}

#------------------------------------------

=item replySubject STRING

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
{   my $subject  = shift;
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

    # String multiple Re's from the end.

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

=item quotePrelude [STRING|FIELD]

Produces a list of lines (usually only one), which will preceed the
quoted body of the message.  STRING must comply to the RFC822 email
address specification, and is usually the content of a C<To> or C<From>
header line.  If a FIELD is specified, the field's body must be
compliant.  Without argument -or when the argument is C<undef>- a
slightly different line is produced.

An characteristic example of the output is

  at Thu Oct 13 04:54:34 1995, him@example.com wrote:

=cut

sub quotePrelude($)
{   my ($self, $user) = @_;
 
    $user = $user->body
       if ref $user && $user->isa('Mail::Message::Field');

    my @addresses = $user ? Mail::Address->parse($user) : ();
    my $address   = $addresses[0];
    my $from      = $address ? $address->name : 'an unknown person';

    my $time    = gmtime $self->timestamp;
    "at $time, $from wrote:\n";
}

#------------------------------------------

=item body2multipart OPTIONS

Create a multipart from a single-part message.  This is needed on the
moment an attachment is added to a single-part body.  If the body
already is a multipart, a nested multipart will be the result.

The OPTIONS are passed to the creation of the multipart-body-object.
See C<Mail::Message::Body::Multipart::new>

=cut

sub body2multipart(@)
{   my $self = shift;

    $self->log(PROGRESS => 'Transformed body to multipart');

    my $multi = Mail::Message::Body::Multipart->new
      ( @_
      , message  => $self
      ) or return;

    my $part = $self->body;
    $part->message($multi);

    $multi->addPart($part);

    $self->body($multi);
    $self;
}

#------------------------------------------

=item build OPTIONS

(Class method)
Simplified message-object builder.  The OPTIONS are a list of
field-name and related values pairs, representing header lines.  The
name C<data> is the only exception, and refers to a list of lines which
has to be stored in the body.  All other names start with an uppercase,
as commonly used in MIME headers.  Names may appear more than once.

Example:

 my $msg = Mail::Message->build(From => 'me@home.nl',
   To => 'you@yourplace.aq', CC => 'everyone@example.com',
   data => [ 'This is', 'the body of', 'the message' ] );

=cut

sub build(@)
{   my $class = shift;

    require Mail::Message::Head::Complete;
    require Mail::Message::Body::Lines;

    my $head  = Mail::Message::Head::Complete->new;
    my $body;

    while(@_)
    {   my ($key, $value) = (shift, shift);
        if($key eq 'data')
        {      $body = Mail::Message::Body::Lines->new(data => $value) }
        else { $head->add($key => $value) }
    }

    $class->new(head => $head, body => $body);
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

This code is beta, version 2.00_10.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
