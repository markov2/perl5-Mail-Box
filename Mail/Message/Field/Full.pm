use strict;
use warnings;

package Mail::Message::Field::Full;
use base 'Mail::Message::Field';

use Mail::Message::Field::Attribute;

use utf8;
use Encode ();
use MIME::QuotedPrint ();

use Carp;
my $atext = q[a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~];  # from RFC

=head1 NAME

Mail::Message::Field::Full - one line of a message header

=head1 SYNOPSIS

 !! THE IMPLEMENTATION OF THIS MODULE IS NOT COMPLETELY FINISHED YET!!

 # Getting to understand the complexity of a header field ...

 my $fast = $msg->head->get('subject');
 my $full = Mail::Message::Field::Full->from($fast);

 my $full = $msg->head->get('subject')->study;  # same
 my $full = $msg->head->study('subject');       # same
 my $full = $msg->get('subject');               # same

 # ... or build a complex header field yourself

 my @encode = (charset => 'jp', use_continuations => 1);

 my $f = Mail::Message::Field::Full->new('Content-Type' => 'text/html');
 $f->addExtra(" and more", @encode);

 $f->addPhrase("text ", @encode);
 $f->addPhrase(" and more text", language => 'en-GB' );

 $f->addAttribute('filename=passwd');
 $f->addAttribute(filename => 'passwd', @encode);

 my $attr = Mail::Message::Field::Attribute->new(...);
 $f->addAttribute($attr);

 $f->addComment('just me', $encode);

=head1 DESCRIPTION

This is the full implementation of a header field: it will be quite slow,
because header fields can be very complex.  Of course, this class delivers
the optimal result, but for a quite large penalty in performance and
memory consumption.

This class supports the common header description from RFC2822 (formerly
RFC822), the extensions with respect to character-set encodings as specified
in RFC2047, and the extensions on language specification and long parameter
wrapping from RFC2231.  If you do not need the latter two, then the
Mail::Message::Field::Fast and Mail::Message::Field::Flex are enough for your
application.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new DATA

Creating a new field object the correct way is a lot of work, because
there is so much freedom in the RFCs, but at the same time so many
restrictions.  Most fields are implemented, but if you have your own
field (and do no want to contribute it to Mail::Box), then simply call
new on your own package.

You have the choice to instantiate the object as string or in prepared
parts:

=over 4

=item * B<new> LINE

=item * B<new> NAME, BODY, [ATTRIBUTES], OPTIONS

=back

The NAME is a wellformed header name (you may use wellformedName()) to
be sure about the casing.  The BODY is a string, one object, or an
ref-array of objects.  In case of objects, they must fit to the
constructor of the field: the types which are accepted may differ.
The optional ATTRIBUTE list contains Mail::Message::Field::Attribute
objects.  Finally, there are some OPTIONS.

=option  attributes ATTRS
=default attributes []

There are various ways to specify these attributes: pass a reference
to an array which list of key-value pairs representing attributes,
or reference to a hash containing these pairs, or an array with
Mail::Message::Field::Attribute objects.

=option  extra STRING
=default extra undef

Text which is appended after the line (preceded by a semicolon).

=option  is_structured BOOLEAN
=default is_structured C<depends>

If the name of the field is known, than the internals know whether the field
is structured or not.  If you call the constructor on your own class which is
derived from Mail::Message::Field::Full, the default is C<true>.  If you have
no own implementation for an unknown field, the boolean is considered C<false>.

For fields which are not known, C<true> means that a
Mail::Message::Field::Structured will be created.  The C<false> value will
create a Mail::Message::Field::Unstructured.

=option  charset STRING
=default charset C<undef>

The body is specified in utf8, and must become 7bits ascii to be
transmited.  Specify a charset to which the multi-byte
utf8 is converted before it gets encoded.  See encode(), which does the
job.

=option  language STRING
=default language C<undef>

The language used can be specified, however is rarely used my mail clients.

=option  encoding 'q'|'Q'|'b'|'B'
=default encoding 'q'

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

my %implementation
 = ( from => 'Addresses', to  => 'Addresses', sender     => 'Addresses'
   , cc   => 'Addresses', bcc => 'Addresses', 'reply-to' => 'Addresses'
   , date => 'Date'
   );

sub new($;$$@)
{   my ($class, $name, $body) = splice(@_, 0, 3);

    my @attrs;
    push @attrs, shift
        while @_ && ref $_[0] && $_[0]->isa('Mail::Message::Field::Attribute');

    my %args   = @_;

    # Attributes preferably stored in array to protect order.
    my $attr = $args{attributes} ||= [];
    $attr    = $args{attribures} = [ %$attr ]   if ref $attr eq 'HASH';
    unshift @$attr, @attrs;

    return $class->SUPER::new(%args, name => $name, body => $body)
       if $class ne __PACKAGE__;

    # Look for best class to suit this field

    (my $type = lc $name) =~ s/^Resent\-//;
    my $myclass
      = $implementation{$type} ? $implementation{$type}
#     : $args{is_structured}   ? 'Structured'
      : $args{is_structured}   ? 'Full'
      :                          'Unstructured';

    $myclass = "Mail::Message::Field::$myclass";
    eval "require $myclass";
    return if $@;

    $myclass->SUPER::new(%args, name => $name, body => $body);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMFF_name}       = $args->{name};
    $self->{MMFF_structured} = $args->{is_structured};

    my $body = $args->{body};
    if(index($body, "\n") >= 0)
    {   # body is already folded: remember how
        $self->{MMFF_body} = $body;
        $body =~ s/\n//g;   # parts store unfolded versions
    }
    $body =~ s/^\s+//;
    $self->{MMFF_parts} = length $body ? [ $body ] : [];

    $self->addExtra($args->{extra})
        if exists $args->{extra};

    my $attr = $args->{attributes};
    while(@$attr)
    {   my $name = shift @$attr;
        if(ref $name) { $self->attribute($name) }
        else          { $self->attribute($name, shift @$attr) }
    }

    $self;
}


#------------------------------------------

=c_method from FIELD, OPTIONS

Convert any FIELD (a Mail::Message::Field object) into a new
Mail::Message::Field::Full object.  This conversion is done the hard
way: the string which is produced by the original object is parsed
again.  Usually, the string which is parsed is exactly the line (or lines)
as found in the original input source, which is a good thing because Full
fields are much more carefull with the actual content.

OPTIONS are passed to the constructor (see new()).  In any case, some
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
    defined $field ?  $class->new($field->Name, $field->folded, @_) : ();
}

#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

=method addAttribute OBJECT|(STRING, OPTIONS)|(NAME,VALUE,OPTIONS)

Add an attribute to the field.  The attributes are added left-to-right into
the string representation of the field, although the order of the attributes
is un-important, according to the RFCs.

You may pass a fully prepared Mail::Message::Field::Attribute OBJECT, if you
like to do all preparations for correct representation of the data yourself.
You may also pass one STRING, which is a fully prepared attribute.  This
STRING will not be changed, so be careful about quoting and encodings.

As third possibility, you can specify an attribute NAME and its VALUE.  An
attribute object will be created for you implicitly in both cases where such
object is not supplied, passing the OPTIONS.
See Mail::Message::Field::Attributes::new() about the available OPTIONS.

The attribute object is returned, however, when continuations are used this
may be an object you already know about.  C<undef> is returned when
construction fails (when the attribute is incorrect).

=examples

 $f->addAttribute('filename=passwd');
 $f->addAttribute(filename => 'passwd', use_continuations => 0);
 my $attr = Mail::Message::Field::Attribute->new(...);
 $f->addAttribute($attr);

=error Attributes cannot be added to unstructured fields

Unstructured fields are free format, attributes are not.  So: it is not
correct to try adding these well-defined strings to an unknown text.

=cut

sub addAttribute($;@)
{   my $self = shift;

    my $attr = ref $_[0] ? shift : Mail::Message::Field::Attribute->new(@_);
    return undef unless $attr;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Attributes cannot be added to unstructured fields:\n"
               . "  Field: ".$self->Name. " Attribute: " .$attr->name);
        return;
    }

    my $name  = lc $attr->name;
    if(my $old =  $self->{MMFF_attrs}{$name})
    {   $old->mergeComponent($attr);
        return $old;
    }
    else
    {   $self->{MMFF_attrs}{$name} = $attr;
        push @{$self->{MMFF_parts}}, $attr;
        delete $self->{MMFF_body};
        return $attr;
    }
}

#------------------------------------------

sub attribute($;$)
{   my ($self, $name) = (shift, shift);
    @_ ? $self->addAttribute($name, shift) : $self->{MMFF_attrs}{lc $name};
}

#------------------------------------------

=method attributes

Returns a list with all attributes, which are all Mail::Message::Field::Attribute
objects.  The attributes are not ordered in any way.  The list may be empty.
Double attributes or continuations are folded into one.

=cut

sub attributes() { values %{shift->{MMFF_attrs}} }

#------------------------------------------

=ci_method createComment STRING, OPTIONS

Create a comment to become part in a field.  Comments are automatically
included within parenthesis.  Matching pairs of parenthesis are
permitted within the STRING.  When a non-matching parenthesis are used,
it is only permitted with an escape (a backslash) in front of them.
These backslashes will be added automatically if needed (don't worry!).
Backslashes will stay, except at the end, where it will be doubled.

The OPTIONS are C<charset>, C<language>, and C<encoding> as always.
See addComment().  The created comment is returned.

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

=method addComment COMMENT, OPTIONS

Creates a comment (see createComment()) and adds it immediately to
this field.  Empty or undefined COMMENTs are ignored.  The created comment
is returned.

=error Comments cannot be added to unstructured fields

Unstructured fields are free format, comments are not.  So: it is not
correct to try adding these well-defined strings to an unknown text.

=cut

sub addComment($@)
{   my $self = shift;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Comments cannot be added to unstructured fields:\n"
                  . "  Field: ".$self->Name. " Comment: @_");
        return;
    }

    return undef
       if ! defined $_[0] || ! CORE::length($_[0]);
 
    my $comment = $self->createComment(@_);
    push @{$self->{MMFF_parts}}, $comment;
    delete $self->{MMFF_body};

    $comment;
}

#------------------------------------------

=method addExtra STRING

Adds a string to the line, which is not an attribute however does start with
a semi-colon.  Empty or undefined STRINGs are ignored.

=error Extras cannot be added to unstructured fields

Unstructured fields are free format, extras are not.  Although an extra is
a nearly free format piece of text preceded by a semi-colon, they do (by
definition) not interfere with other structured data in fields.
So: it is not correct to try adding these to an fully free formatted text
because you are never sure the data can be regained correctly.

=cut

sub addExtra($)
{   my ($self, $extra) = @_;

    unless($self->{MMFF_structured})
    {   $self->log(ERROR => "Extras cannot be added to unstructured fields:\n"
               . "  Field: ".$self->Name. " Extra: ".$extra);
        return;
    }

    if(defined $extra && length $extra)
    {   push @{$self->{MMFF_parts}}, '; '.$extra;
        delete $self->{MMFF_body};
    }

    $self;
}

#------------------------------------------

=ci_method createPhrase STRING, OPTIONS

A phrase is a text which plays a well defined role.  This is the main difference
with comments, which have do specified meaning.  Some special characters
in the phrase will cause it to be surrounded with double quotes: do not specify
them yourself.

The OPTIONS are C<charset>, C<language>, and C<encoding> as always.
See addPhrase().

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

=method addPhrase STRING, OPTIONS

Create a phrase (see createPhrase()) and immediately add it to this field.
Empty or undefined values of STRING are ignored.  The created phrase is
returned.

=cut

sub addPhrase($)
{   my ($self, $string) = (shift, shift);

    return undef
         unless defined $string && CORE::length($string);

    my $phrase = $self->createPhrase($string);

    push @{$self->{MMFF_parts}}, $phrase;
    delete $self->{MMFF_body};
    $phrase;
}

#------------------------------------------

sub clone()
{   my $self = shift;
    croak;
}

#------------------------------------------

sub length()
{   my $self = shift;
    croak;
}

#------------------------------------------

=head2 Access to the Field

=cut

#------------------------------------------

sub name() { lc shift->{MMFF_name}}

#------------------------------------------

sub Name() { shift->{MMFF_name}}

#------------------------------------------

sub folded(;$)
{   my $self = shift;
    return $self->{MMFF_name}.':'.$self->foldedBody
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->{MMFF_name}. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfoldedBody($;@)
{   my $self = shift;
    if(@_)
    {   my $part = join ' ', @_;
        $self->{MMFF_body}  = $self->fold($self->{MMFF_name}, $part);
        $self->{MMFF_parts} = [ $part ];
        return $part;
    }

    join(' ', @{$self->{MMFF_parts}});
}

#------------------------------------------

sub foldedBody($)
{   my ($self, $body) = @_;

       if(@_==2) { $self->{MMFF_body} = $body }
    elsif($body = $self->{MMFF_body}) { ; }
    else
    {   # Create a new folded body from the parts.
        $self->{MMFF_body} = $body
           = $self->fold($self->{MMFF_name}, join(' ', @{$self->{MMFF_parts}}));
    }

    wantarray ? (split /^/, $body) : $body;
}

#------------------------------------------

=method decodedBody OPTIONS

Returns the unfolded body of the field, where encodings are resolved.  The
returned line will still contain comments and such.  The OPTIONS are passed
to the decoder, see decode().

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

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method encode STRING, OPTIONS

Encode the (possibly utf8 encoded) STRING to a string which is acceptable
to the RFC2047 definition of a header: only containing us-ascii characters.

=option  encoding 'q'|'Q'|'b'|'B'
=default encoding 'q'

The character encoding to be used.  With C<q> or C<Q>, quoted-printable
encoding will be used.  With C<b> or C<B>, base64 encoding will be taken.

=option  charset STRING
=default charset 'us-ascii'

STRING is an utf8 string which has to be translated into any byte-wise
character set for transport, because MIME-headers can only contain ascii
characters.

=option  language STRING
=default language C<undef>

RFC2231 defines how to specify language encodings in encoded words.  The
STRING is a strandard iso language name.

=option  force BOOLEAN
=default force 0

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

The RFCs only permit base64 (C<b> or C<B>) or quoted-printable (C<q> or C<Q>)
encoding.  Other than these four options are illegal.

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

        my $take = 72 - CORE::length($pre);
        while(CORE::length($qp) > $take)
        {   $qp =~ s#^(.{$take}.?.?[^=][^=])## or warn $qp;
            $ready .= "$pre$1?= ";
        }
        $ready .= "$pre$qp?=" if CORE::length $qp;
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

=option  is_text => BOOLEAN
=default is_text => 1

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

    Encode::encode($charset, $decoded, 0);
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
        $phrase =~ s/\s+$//g;
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

        last unless $string =~ s/(\s*[$atext]+(?:\.[$atext]+)*)//o;

        $atom .= $1;
    }

    ($atom, $string, $comment);
}

#------------------------------------------

1;
