use strict;
use warnings;

package Mail::Message::Field::Full;
use base 'Mail::Message::Field';

use utf8;
use Encode ();
use MIME::QuotedPrint ();
use Storable 'dclone';

use Mail::Message::Field::Structured;
use Mail::Message::Field::Unstructured;
use Mail::Message::Field::Addresses;
use Mail::Message::Field::URIs;

my $atext = q[a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~];  # from RFC

=chapter NAME

Mail::Message::Field::Full - construct one smart line in a message header

=chapter SYNOPSIS

 !! UNDER CONSTRUCTION
 !! The details of this module are NOT FINISHED yet
 !! Most parts are already usable, however.  With care!

 # Getting to understand the complexity of a header field ...

 my $fast = $msg->head->get('subject');
 my $full = Mail::Message::Field::Full->from($fast);

 my $full = $msg->head->get('subject')->study;  # same
 my $full = $msg->head->study('subject');       # same
 my $full = $msg->get('subject');               # same

 # ... or build a complex header field yourself

 my $f = Mail::Message::Field::Full->new('To');
 my $f = Mail::Message::Field::Full->new('Subject: hi!');
 my $f = Mail::Message::Field::Full->new(Subject => 'hi!');

=chapter DESCRIPTION

This is the I<full> implementation of a header field: it has I<full>
understanding of all predefined header fields.  These objects will be
quite slow, because header fields can be very complex.  Of course, this
class delivers the optimal result, but for a quite large penalty in
performance and memory consumption.  Are you willing to accept?

This class supports the common header description from RFC2822 (formerly
RFC822), the extensions with respect to character set encodings as specified
in RFC2047, and the extensions on language specification and long parameter
wrapping from RFC2231.  If you do not need the latter two, then the
M<Mail::Message::Field::Fast> and M<Mail::Message::Field::Flex>
are enough for your application.

=chapter OVERLOADED

=overload stringification

In string context, the decoded body is returned, as if M<decodedBody()>
would have been called.

=cut

use overload '""' => sub { shift->decodedBody };

#------------------------------------------

=chapter METHODS

=c_method new DATA

Creating a new field object the correct way is a lot of work, because
there is so much freedom in the RFCs, but at the same time so many
restrictions.  Most fields are implemented, but if you have your own
field (and do no want to contribute it to MailBox), then simply call
new on your own package.

You have the choice to instantiate the object as string or in prepared
parts:

=over 4

=item * B<new> LINE, OPTIONS

Pass a LINE as it could be found in a file: a (possibly folded) line
which is terminated by a new-line.

=item * B<new> NAME, [BODY], OPTIONS

A set of values which shape the line.

=back

The NAME is a wellformed header name (you may use wellformedName()) to
be sure about the casing.  The BODY is a string, one object, or an
ref-array of objects.  In case of objects, they must fit to the
constructor of the field: the types which are accepted may differ.
The optional ATTRIBUTE list contains M<Mail::Message::Field::Attribute>
objects.  Finally, there are some OPTIONS.

=option  charset STRING
=default charset undef

The body is specified in utf8, and must become 7-bits ascii to be
transmited.  Specify a charset to which the multi-byte utf8 is converted
before it gets encoded.  See M<encode()>, which does the job.

=option  language STRING
=default language undef

The language used can be specified, however is rarely used my mail clients.

=option  encoding 'q'|'Q'|'b'|'B'
=default encoding C<'q'>

Non-ascii characters are encoded using Quoted-Printable ('q' or 'Q') or
Base64 ('b' or 'B') encoding.

=option  force BOOLEAN
=default force false

Enforce encoding in the specified charset, even when it is not needed
because the body does not contain any non-ascii characters.

=examples

 my $s = Mail::Message::Field::Full->new('Subject: Hello World');
 my $s = Mail::Message::Field::Full->new('Subject', 'Hello World');

 my @attrs   = (Mail::Message::Field::Attribute->new(...), ...);
 my @options = (extra => 'the color blue');
 my $t = Mail::Message::Field::Full->new(To => \@addrs, @attrs, @options);

=cut

my %implementation;

BEGIN {
   $implementation{$_} = 'Addresses' foreach
      qw/from to sender cc bcc reply-to envelope-to
         resent-from resent-to resent-cc resent-bcc resent-reply-to
         resent-sender
         x-beenthere errors-to mail-follow-up x-loop delivered-to
         original-sender x-original-sender/;
   $implementation{$_} = 'URIs' foreach
      qw/list-help list-post list-subscribe list-unsubscribe list-archive
         list-owner/;
   $implementation{$_} = 'Structured' foreach
      qw/content-disposition content-type/;
#  $implementation{$_} = 'Date' foreach
#     qw/date resent-date/;
}

sub new($;$$@)
{   my $class  = shift;
    my $name   = shift;
    my $body   = @_ % 2 ? shift : undef;
    my %args   = @_;

    $body      = delete $args{body} if defined $args{body};
    unless(defined $body)
    {   (my $n, $body) = split /\s*\:\s*/s, $name, 2;
        $name = $n if defined $body;
    }
   
    return $class->SUPER::new(%args, name => $name, body => $body)
       if $class ne __PACKAGE__;

    # Look for best class to suit this field
    my $myclass = 'Mail::Message::Field::'
                . ($implementation{lc $name} || 'Unstructured');

    $myclass->SUPER::new(%args, name => $name, body => $body);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    $self->{MMFF_name}       = $args->{name};

    my $body = $args->{body};

       if(!defined $body || !length $body || ref $body) { ; } # no body yet
    elsif(index($body, "\n") >= 0)
         { $self->foldedBody($body) }        # body is already folded
    else { $self->unfoldedBody($body) }      # body must be folded

    $self;
}

#------------------------------------------

sub clone() { dclone(shift) }

#------------------------------------------

sub name() { lc shift->{MMFF_name}}

#------------------------------------------

sub Name() { shift->{MMFF_name}}

#------------------------------------------

sub folded()
{   my $self = shift;
    return $self->{MMFF_name}.':'.$self->foldedBody
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->{MMFF_name}. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfoldedBody($;$)
{   my ($self, $body) = (shift, shift);

    if(defined $body)
    {    $self->foldedBody(scalar $self->fold($self->{MMFF_name}, $body));
         return $body;
    }

    $body = $self->foldedBody;
    $body =~ s/^ //;
    $body =~ s/\n//g;
    $body;
}

#------------------------------------------

sub foldedBody($)
{   my ($self, $body) = @_;

    if(@_==2)
    {    $self->parse($body);
         $body =~ s/^\s*/ /;
         $self->{MMFF_body} = $body;
    }
    elsif(defined($body = $self->{MMFF_body})) { ; }
    else
    {   # Create a new folded body from the parts.
        $self->{MMFF_body} = $body
           = $self->fold($self->{MMFF_name}, $self->produceBody);
    }

    wantarray ? (split /^/, $body) : $body;
}

#------------------------------------------

=section Constructors

=c_method from FIELD, OPTIONS

Convert any FIELD (a M<Mail::Message::Field> object) into a new
M<Mail::Message::Field::Full> object.  This conversion is done the hard
way: the string which is produced by the original object is parsed
again.  Usually, the string which is parsed is exactly the line (or lines)
as found in the original input source, which is a good thing because Full
fields are much more carefull with the actual content.

OPTIONS are passed to the constructor (see M<new()>).  In any case, some
extensions of this Full field class is returned.  It depends on which
field is created what kind of class we get.

=examples

 my $fast = $msg->head->get('subject');
 my $full = Mail::Message::Field::Full->from($fast);

 my $full = $msg->head->get('subject')->study;  # same
 my $full = $msg->head->study('subject');       # same
 my $full = $msg->get('subject');               # same

=cut

sub from($@)
{   my ($class, $field) = (shift, shift);
    defined $field ?  $class->new($field->Name, $field->foldedBody, @_) : ();
}

#------------------------------------------

=section Access to the body

=method decodedBody OPTIONS

Returns the unfolded body of the field, where encodings are resolved.  The
returned line will still contain comments and such.  The OPTIONS are passed
to the decoder, see M<decode()>.

BE WARNED: if the field is a structured field, the content may change syntax,
because of encapsulated special characters.  By default, the body is decoded
as text, which results in a small difference within comments as well
(read the RFC).

=cut

sub decodedBody()
{   my $self = shift;
    $self->decode($self->unfoldedBody, @_);
}

#------------------------------------------

=section Access to the content

=ci_method createComment STRING, OPTIONS

Create a comment to become part in a field.  Comments are automatically
included within parenthesis.  Matching pairs of parenthesis are
permitted within the STRING.  When a non-matching parenthesis are used,
it is only permitted with an escape (a backslash) in front of them.
These backslashes will be added automatically if needed (don't worry!).
Backslashes will stay, except at the end, where it will be doubled.

The OPTIONS are C<charset>, C<language>, and C<encoding> as always.
The created comment is returned.

=cut

sub createComment($@)
{   my ($thing, $comment) = (shift, shift);

    $comment = $thing->encode($comment, @_)
        if @_; # encoding required...

    # Correct dangling parenthesis
    local $_ = $comment;               # work with a copy
    s#\\[()]#xx#g;                     # remove escaped parens
    s#[^()]#x#g;                       # remove other chars
    while( s#\(([^()]*)\)#x$1x# ) {;}  # remove pairs of parens

    substr($comment, CORE::length($_), 0, '\\')
        while s#[()][^()]*$##;         # add escape before remaining parens

    $comment =~ s#\\+$##;              # backslash at end confuses
    "($comment)";
}

#------------------------------------------

=ci_method createPhrase STRING, OPTIONS

A phrase is a text which plays a well defined role.  This is the main
difference with comments, which have do specified meaning.  Some special
characters in the phrase will cause it to be surrounded with double
quotes: do not specify them yourself.

The OPTIONS are C<charset>, C<language>, and C<encoding> as always.

=cut

sub createPhrase($)
{   my $self = shift;
    local $_ = shift;
    $_ =  $self->encode($_, @_)
        if @_;  # encoding required...

    if( m/[^$atext]/ )
    {   s#\\#\\\\#g;
        s#"#\\"#g;
        $_ = qq["$_"];
    }

    $_;
}

#------------------------------------------

=method beautify

For structured header fields, this removes the original encoding of the
field's body (the format as it was offered to M<parse()>), therefore the
next request for the field will have to re-produce the read data clean
and nice.  For unstructured bodies, this method doesn't do a thing.

=cut

sub beautify() { shift }

#------------------------------------------

=section Internals

=method encode STRING, OPTIONS

Encode the (possibly utf8 encoded) STRING to a string which is acceptable
to the RFC2047 definition of a header: only containing us-ascii characters.

=option  encoding 'q'|'Q'|'b'|'B'
=default encoding C<'q'>

The character encoding to be used.  With C<q> or C<Q>, quoted-printable
encoding will be used.  With C<b > or C<B >, base64 encoding will be taken.

=option  charset STRING
=default charset C<'us-ascii'>

STRING is an utf8 string which has to be translated into any byte-wise
character set for transport, because MIME-headers can only contain ascii
characters.

=option  language STRING
=default language undef

RFC2231 defines how to specify language encodings in encoded words.  The
STRING is a strandard iso language name.

=option  force BOOLEAN
=default force <flase>

Encode the string, even when it only contains us-ascii characters.  By
default, this is off because it decreases readibility of the produced
header fields.

=warning Illegal character in charset '$charset'

The field is created with an utf8 string which only contains data from the
specified character set.  However, that character set can never be a valid
name because it contains characters which are not permitted.

=warning Illegal character in language '$lang'

The field is created with data which is specified to be in a certain language,
however, the name of the language cannot be valid: it contains characters
which are not permitted by the RFCs.

=warning Illegal encoding '$encoding', used 'q'

The RFCs only permit base64 (C<b > or C<B >) or quoted-printable
(C<q> or C<Q>) encoding.  Other than these four options are illegal.

=cut

sub encode($@)
{   my ($self, $utf8, %args) = @_;

    my ($charset, $lang, $encoding);

    if($charset = $args{charset})
    {   $self->log(WARNING => "Illegal character in charset '$charset'")
            if $charset =~ m/[\x00-\ ()<>@,;:"\/[\]?.=\\]/;
    }
    else { $charset = 'us-ascii' }

    if($lang = $args{language})
    {   $self->log(WARNING => "Illegal character in language '$lang'")
            if $lang =~ m/[\x00-\ ()<>@,;:"\/[\]?.=\\]/;
    }

    if($encoding = $args{encoding})
    {   unless($encoding =~ m/^[bBqQ]$/ )
        {   $self->log(WARNING => "Illegal encoding '$encoding', used 'q'");
            $encoding = 'q';
        }
    }
    else { $encoding = 'q' }

    my $encoded  = Encode::encode($charset, $utf8, 0);

    no utf8;

    my $pre      = '=?'. $charset. ($lang ? '*'.$lang : '') .'?'.$encoding.'?';
    my $ready    = '';

    if(lc $encoding eq 'q')
    {   # Quoted printable encoding
        my $qp   = $encoded;
        $qp      =~ s#([\x00-\x1F=\x7F-\xFF])#sprintf "=%02X", ord $1#ge;

        return $qp           # string only contains us-ascii?
           if !$args{force} && $qp eq $utf8;

        $qp      =~ s#([_\?])#sprintf "=%02X", ord $1#ge;
        $qp      =~ s/ /_/g;

        my $take = 70 - CORE::length($pre);
        while(CORE::length($qp) > $take+1)
        {   $qp =~ s#^(.{$take}.?.?[^=][^=])## or warn $qp;
            $ready .= "$pre$1?= ";
        }
        $ready .= "$pre$qp?=" if CORE::length($qp);
    }

    else
    {   # base64 encoding
        require MIME::Base64;
        my $maxchars = int((74-CORE::length($pre))/4) *4;
        my $bq       = MIME::Base64::encode_base64($encoded);
        $bq =~ s/\s*//gs;
        while(CORE::length($bq) > $maxchars)
        {   $ready .= $pre . substr($bq, 0, $maxchars, '') . '?= ';
        }
        $ready .= "$pre$bq?=";
    }

    $ready;
}

#------------------------------------------

=ci_method decode STRING, OPTIONS

Decode field encoded STRING to an utf8 string.  The input STRING is part of
a header field, and as such, may contain encoded words in C<=?...?.?...?=>
format defined by RFC2047.  The STRING may contain multiple encoded parts,
maybe using different character sets.

Be warned:  you MUST first interpret the field into parts, like phrases and
comments, and then decode each part separately, otherwise the decoded text
may interfere with your markup characters.

Be warned: language information, which is defined in RFC2231, is ignored.

=option  is_text BOOLEAN
=default is_text C<1>

Encoding on text is slightly more complicated than encoding structured data,
because it contains blanks.  Visible blanks have to be ignored between two
encoded words in the text, but not when an encoded word follows or preceeds
an unencoded word.  Phrases and comments are texts.

=example

 print Mail::Message::Field::Full->decode('=?iso-8859-1?Q?J=F8rgen?=');
    # prints   JE<0slash>rgen

=cut

sub _decoder($$$)
{   my ($charset, $encoding, $encoded) = @_;
    $charset   =~ s/\*[^*]+$//;   # string language, not used
    $charset ||= 'us-ascii';

    my $decoded;
    if(lc($encoding) eq 'q')
    {   # Quoted-printable encoded
        $encoded =~ s/_/ /g;
        $decoded = MIME::QuotedPrint::decode_qp($encoded);
    }
    elsif(lc($encoding) eq 'b')
    {   # Base64 encoded
        require MIME::Base64;
        $decoded = MIME::Base64::decode_base64($encoded);
    }
    else
    {   # unknown encodings ignored
        return $encoded;
    }

    Encode::decode($charset, $decoded, 0);
}

sub decode($@)
{   my ($self, $encoded, %args) = @_;
    if(defined $args{is_text} ? $args{is_text} : 1)
    {  # in text, blanks between encoding must be removed, but otherwise kept :(
       # dirty trick to get this done: add an explicit blank.
       $encoded =~ s/\?\=\s(?!\s*\=\?|$)/_?= /gs;
    }
    $encoded =~ s/\=\?([^?\s]*)\?([^?\s]*)\?([^?\s]*)\?\=\s*/_decoder($1,$2,$3)/gse;

    $encoded;
}

#------------------------------------------

=section Parsing

=method parse STRING

Get the detailed information from the STRING, and store the data found
in the field object.  The accepted input is very field type dependent.
Unstructured fields do no parsing whatsoever.

=cut

sub parse($) { shift }

#------------------------------------------

=ci_method consumePhrase STRING

Take the STRING, and try to strip-off a valid phrase.  In the obsolete
phrase syntax, any sequence of words is accepted as phrase (as long as
certain special characters are not used).  RFC2882 is stricter: only
one word or a quoted string is allowed.  As always, the obsolete
syntax is accepted, and the new syntax is produced.

This method returns two elements: the phrase (or undef) followed
by the resulting string.  The phrase will be removed from the optional
quotes.  Be warned that C<""> will return an empty, valid phrase.

=example

 my ($phrase, $rest) = $field->consumePhrase( q["hi!" <sales@example.com>] );

=cut

sub consumePhrase($)
{   my ($thing, $string) = @_;

    if($string =~ s/^\s*\"((?:[^"\\]*|\\.)*)\"// )
    {   (my $phrase = $1) =~ s/\\\"/"/g;
        return ($phrase, $string);
    }

    if($string =~ s/^\s*([$atext\ \t.]+)//o )
    {   (my $phrase = $1) =~ s/\s+$//;
        return CORE::length($phrase) ? ($phrase, $string) : (undef, $_[1]);
    }

    (undef, $string);
}

#------------------------------------------

=ci_method consumeComment STRING

Try to read a comment from the STRING.  When successful, the comment
without encapsulation parenthesis is returned, together with the rest
of the string.

=cut

sub consumeComment($)
{   my ($thing, $string) = @_;

    return (undef, $string)
        unless $string =~ s/^\s*\(((?:[^)\\]+|\\.)*)\)//;

    my $comment = $1;
    while(1)
    {   (my $count = $comment) =~ s/\\./xx/g;

        last if $count =~ tr/(//  ==  $count =~ tr/)//;

        return (undef, $_[1])
            unless $string =~ s/^((?:[^)\\]+|\\.)*)\)//;

        $comment .= ')'.$1;
    }

    $comment =~ s/\\([()])/$1/g;
    ($comment, $string);
}

#------------------------------------------

=method consumeDotAtom STRING

Returns three elemens: the atom-text, the rest string, and the
concatenated comments.  Both atom and comments can be undef.

=cut

sub consumeDotAtom($)
{   my ($self, $string) = @_;
    my ($atom, $comment);

    while(1)
    {   (my $c, $string) = $self->consumeComment($string);
        if(defined $c) { $comment .= $c; next }

        last unless $string =~ s/^\s*([$atext]+(?:\.[$atext]+)*)//o;

        $atom .= $1;
    }

    ($atom, $string, $comment);
}

#------------------------------------------

=method produceBody
Produce the text for the field, based on the information stored within the
field object.

Usually, you wish the exact same line as was found in the input source
of a message.  But when you have created a field yourself, it should get
formatted.  You may call M<beautify()> on a preformatted field to enforce
a call to this method when the field is needed later.

=cut
                                                                                
sub produceBody() { die }

#------------------------------------------

=section Error handling

=cut


1;
