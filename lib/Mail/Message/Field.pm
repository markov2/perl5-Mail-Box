use strict;
use warnings;

package Mail::Message::Field;
use base 'Mail::Reporter';

use Carp;
use Mail::Address;
use Date::Format 'strftime';
use IO::Handle;

our %_structured;  # not to be used directly: call isStructured!
my $default_wrap_length = 78;

=encoding utf8

=chapter NAME

Mail::Message::Field - one line of a message header

=chapter SYNOPSIS

 my $field = Mail::Message::Field->new(From => 'fish@tux.aq');
 print $field->name;
 print $field->body;
 print $field->comment;
 print $field->content;  # body & comment
 $field->print(\*OUT);
 print $field->string;
 print "$field\n";
 print $field->attribute('charset') || 'us-ascii';

=chapter DESCRIPTION

This implementation follows the guidelines of rfc2822 as close as possible,
and may there produce a different output than implementations based on
the obsolete rfc822.  However, the old output will still be accepted.

These objects each store one header line, and facilitates access routines to
the information hidden in it.  Also, you may want to have a look at the
added methods of a message:

 my @from    = $message->from;
 my $sender  = $message->sender;
 my $subject = $message->subject;
 my $msgid   = $message->messageId;

 my @to      = $message->to;
 my @cc      = $message->cc;
 my @bcc     = $message->bcc;
 my @dest    = $message->destinations;

 my $other   = $message->get('Reply-To');

=chapter OVERLOADED

=overload ""

(stringification) produces the unfolded body of the field, which may
be what you expect.  This is what makes what the field object seems
to be a simple string. The string is produced by M<unfoldedBody()>.

=example

 print $msg->get('subject');  # via overloading
 print $msg->get('subject')->unfoldedBody; # same

 my $subject = $msg->get('subject') || 'your mail';
 print "Re: $subject\n";

=overload 0+

(numification) When the field is numeric, the value will be returned.
The result is produced by M<toInt()>.  If the value is not correct,
a C<0> is produced, to simplify calculations.

=overload bool
Always true, to make it possible to say C<if($field)>.

=overload cmp
(string comparison) Compare the unfolded body of a field with an other
field or a string, using the buildin C<cmp>.

=overload <=>
(numeric comparison) Compare the integer field contents with something
else.

=example
 if($msg->get('Content-Length') > 10000) ...
 if($msg->size > 10000) ... ; # same, but better

=cut

use overload
    qq("") => sub { $_[0]->unfoldedBody }
 , '0+'    => sub { $_[0]->toInt || 0 }
 , bool    => sub {1}
 , cmp     => sub { $_[0]->unfoldedBody cmp "$_[1]" }
 , '<=>'   => sub { $_[2] ? $_[1] <=> $_[0]->toInt : $_[0]->toInt <=> $_[1] }
 , fallback => 1;

#------------------------------------------

=chapter METHODS

=section Constructors

=c_method new $data

See M<Mail::Message::Field::Fast::new()>,
M<Mail::Message::Field::Flex::new()>,
and M<Mail::Message::Field::Full::new()>.
By default, a C<Fast> field is produced.

=cut

sub new(@)
{   my $class = shift;
    if($class eq __PACKAGE__)  # bootstrap
    {   require Mail::Message::Field::Fast;
        return Mail::Message::Field::Fast->new(@_);
    }
    $class->SUPER::new(@_);
}


=method clone
Create a copy of this field object.
=cut

#------------------------------------------

=section The field

=method length
Returns the total length of the field in characters, which includes the
field's name, body and folding characters.

=cut

sub length { length shift->folded }

=ci_method isStructured
Some fields are described in the RFCs as being I<structured>: having a
well described syntax.  These fields have common ideas about comments
and the like, what they do not share with unstructured fields, like
the C<Subject> field.

=examples
 my $field = Mail::Message::Field->new(From => 'me');
 if($field->isStructured)

 Mail::Message::Field->isStructured('From');

=cut

BEGIN {
%_structured = map { (lc($_) => 1) }
  qw/To Cc Bcc From Date Reply-To Sender
     Resent-Date Resent-From Resent-Sender Resent-To Return-Path
     List-Help List-Post List-Unsubscribe Mailing-List
     Received References Message-ID In-Reply-To
     Content-Type Content-Disposition Content-ID
     Delivered-To
     MIME-Version
     Precedence
     Status/;
} 

sub isStructured(;$)
{   my $name  = ref $_[0] ? shift->name : $_[1];
    exists $_structured{lc $name};
}

=method print [$fh]
Print the whole header-line to the specified file-handle. One line may
result in more than one printed line, because of the folding of long
lines.  The $fh defaults to the selected handle.
=cut

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print(scalar $self->folded);
}

=method string [$wrap]
Returns the field as string.  By default, this returns the same as
M<folded()>. However, the optional $wrap will cause to re-fold to take
place (without changing the folding stored inside the field).
=cut

sub toString(;$) {shift->string(@_)}
sub string(;$)
{   my $self  = shift;
    return $self->folded unless @_;

    my $wrap  = shift || $default_wrap_length;
    my $name  = $self->Name;
    my @lines = $self->fold($name, $self->unfoldedBody, $wrap);
    $lines[0] = $name . ':' . $lines[0];
    wantarray ? @lines : join('', @lines);
}

=method toDisclose
Returns whether this field can be disclosed to other people, for instance
when sending the message to an other party.  Returns a C<true> or C<false>
condition.
See also M<Mail::Message::Head::Complete::printUndisclosed()>.
=cut

sub toDisclose()
{   shift->name !~ m!^(?: (?:x-)?status
                      |   (?:resent-)?bcc
                      |   Content-Length
                      |   x-spam-
                      ) $!x;
}

=method nrLines
Returns the number of lines needed to display this header-line.
=cut

sub nrLines() { my @l = shift->foldedBody; scalar @l }

=method size
Returns the number of bytes needed to display this header-line, Same
as M<length()>.
=cut

*size = \&length;

#------------------------------------------

=section Access to the name

=method name
Returns the name of this field, with all characters lower-cased for
ease of comparison.  See M<Name()> as well.

=method Name
Returns the name of this field in original casing.  See M<name()> as well.

=method wellformedName [STRING]
(Instance method class method)
As instance method, the current field's name is correctly formatted
and returned.  When a STRING is used, that one is formatted.

=examples
 print Mail::Message::Field->Name('content-type')
   # -->  Content-Type

 my $field = $head->get('date');
 print $field->Name;
   # -->  Date

=cut

# attempt to change the case of a tag to that required by RFC822. That
# being all characters are lowercase except the first of each
# word. Also if the word is an `acronym' then all characters are
# uppercase. We, rather arbitrarily, decide that a word is an acronym
# if it does not contain a vowel and isn't the well-known 'Cc' or
# 'Bcc' headers.

my %wf_lookup
  = qw/mime MIME  ldap LDAP  soap SOAP  swe SWE
       bcc Bcc  cc Cc  id ID/;

sub wellformedName(;$)
{   my $thing = shift;
    my $name = @_ ? shift : $thing->name;

    join '-',
       map { $wf_lookup{lc $_} || ( /[aeiouyAEIOUY]/ ? ucfirst lc : uc ) }
          split /\-/, $name, -1;
}

#------------------------------------------

=section Access to the body

=method folded
Returns the folded version of the whole header.  When the header is
shorter than the wrap length, a list of one line is returned.  Otherwise
more lines will be returned, all but the first starting with at least
one blank.  See also M<foldedBody()> to get the same information without
the field's name.

In scalar context, the lines are delived into one string, which is
a little faster because that's the way they are stored internally...

=examples
 my @lines = $field->folded;
 print $field->folded;
 print scalar $field->folded; # faster

=cut

sub folded { shift->notImplemented }

=method body
This method may be what you want, but usually, the M<foldedBody()> and
M<unfoldedBody()> are what you are looking for.  This method is
cultural heritage, and should be avoided.

Returns the body of the field.  When this field is structured, it will
be B<stripped> from everything what is behind the first semi-color (C<;>).
In any case, the string is unfolded.  
Whether the field is structured is defined by M<isStructured()>.
=cut

sub body()
{   my $self = shift;
    my $body = $self->unfoldedBody;
    return $body unless $self->isStructured;

    $body =~ s/\s*\;.*//s;
    $body;
}

=method foldedBody [$body]
Returns the body as a set of lines. In scalar context, this will be one line
containing newlines.  Be warned about the newlines when you do
pattern-matching on the result of thie method.

The optional $body argument changes the field's body.  The folding of the
argument must be correct.
=cut

sub foldedBody { shift->notImplemented }

=method unfoldedBody [$body, [$wrap]]
Returns the body as one single line, where all folding information (if
available) is removed.  This line will also NOT end on a new-line.

The optional $body argument changes the field's body.  The right folding is
performed before assignment.  The $wrap may be specified to enforce a
folding size.

=examples

 my $body = $field->unfoldedBody;
 print "$field";   # via overloading

=cut

sub unfoldedBody { shift->notImplemented }

=ci_method stripCFWS [STRING]
Remove the I<comments> and I<folding white spaces> from the STRING.  Without
string and only as instance method, the M<unfoldedBody()> is being stripped
and returned.

WARNING: This operation is only allowed for structured header fields (which
are defined by the various RFCs as being so.  You don't want parts within
braces which are in the Subject header line to be removed, to give an
example.

=cut

sub stripCFWS($)
{   my $thing  = shift;

    # get (folded) data
    my $string = @_ ? shift : $thing->foldedBody;

    # remove comments
    my $r          = '';
    my $in_dquotes = 0;
    my $open_paren = 0;

    my @s = split m/([()"])/, $string;
    while(@s)
    {   my $s = shift @s;

           if(CORE::length($r)&& substr($r, -1) eq "\\")  { $r .= $s }
        elsif($s eq '"')   { $in_dquotes = not $in_dquotes; $r .= $s }
        elsif($s eq '(' && !$in_dquotes) { $open_paren++ }
        elsif($s eq ')' && !$in_dquotes) { $open_paren-- }
        elsif($open_paren) {}  # in comment
        else               { $r .= $s }
    }

    # beautify and unfold at the same time
    for($r)
    {  s/\s+/ /gs;
       s/\s+$//;
       s/^\s+//;
    }

    $r;
}

#------------------------------------------

=section Access to the content

=method comment [STRING]

Returns the unfolded comment (part after a semi-colon) in a structureed
header-line. optionally after setting it to a new STRING first.
When C<undef> is specified as STRING, the comment is removed.
Whether the field is structured is defined by M<isStructured()>.

The I<comment> part of a header field often contains C<attributes>.  Often
it is preferred to use M<attribute()> on them.

=cut

sub comment(;$)
{   my $self = shift;
    return undef unless $self->isStructured;

    my $body = $self->unfoldedBody;

    if(@_)
    {   my $comment = shift;
        $body    =~ s/\s*\;.*//;
        $body   .= "; $comment" if defined $comment && CORE::length($comment);
        $self->unfoldedBody($body);
        return $comment;
    }
 
    $body =~ s/.*?\;\s*// ? $body : '';
}

sub content() { shift->unfoldedBody }  # Compatibility

=method attribute $name, [$value]
Get the value of an attribute, optionally after setting it to a new value.
Attributes are part of some header lines, and hide themselves in the
comment field.  If the attribute does not exist, then C<undef> is
returned.  The attribute is still encoded.

=examples

 my $field = Mail::Message::Field->new(
  'Content-Type: text/plain; charset="us-ascii"');

 print $field->attribute('charset');
   # --> us-ascii

 print $field->attribute('bitmap') || 'no'
   # --> no

 $field->atrribute(filename => '/tmp/xyz');
 $field->print;
   # --> Content-Type: text/plain; charset="us-ascii";
   #       filename="/tmp/xyz"
   # Automatically folded, and no doubles created.

=cut

sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $body  = $self->unfoldedBody;

    unless(@_)
    {   if($body =~ m/\b$attr\s*\=\s*
                      ( "( (?> [^\\"]+|\\. )* )"
                      | ([^";\s]*)
                      )/xi)
        {   (my $val = $+) =~ s/\\(.)/$1/g;
            return $val;
        }
        return undef;
    }

    my $value = shift;
    unless(defined $value)  # remove attribute
    {   for($body)
        {      s/\b$attr\s*=\s*"(?>[^\\"]|\\.)*"//i
            or s/\b$attr\s*=\s*[;\s]*//i;
        }
        $self->unfoldedBody($body);
        return undef;
    }

    (my $quoted = $value) =~ s/(["\\])/\\$1/g;

    for($body)
    {       s/\b$attr\s*=\s*"(?>[^\\"]|\\.){0,1000}"/$attr="$quoted"/i
         or s/\b$attr\s*=\s*[^;\s]*/$attr="$quoted"/i
         or do { $_ .= qq(; $attr="$quoted") }
    }

    $self->unfoldedBody($body);
    $value;
}

#------------------------------------------

=method attributes
Returns a list of key-value pairs, where the values are not yet decoded.
=example
 my %attributes = $head->get('Content-Disposition')->attributes;
=cut

sub attributes()
{   my $self  = shift;
    my $body  = $self->unfoldedBody;

    my @attrs;
    while($body =~ m/\b(\w+)\s*\=\s*
                       ( "( (?: [^"]|\\" )* )"
                       | '( (?: [^']|\\' )* )'
                       | ([^;\s]*)
                       )
                    /xig)
    {   push @attrs, $1 => $+;
    }

    @attrs;
}

#------------------------------------------

=method toInt

Returns the value which is related to this field as integer.  A check is
performed whether this is right.

=warning Field content is not numerical: $content

The numeric value of a field is requested (for instance the C<Lines> or
C<Content-Length> fields should be numerical), however the data contains
weird characters.

=cut

sub toInt()
{   my $self = shift;
    return $1 if $self->body =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not numerical: ". $self->toString);

    return undef;
}

#------------------------------------------

=ci_method toDate [$time]

Convert a timestamp into an rfc2822 compliant date format.  This differs
from the default output of C<localtime> in scalar context.  Without
argument, the C<localtime> is used to get the current time. $time can
be specified as one numeric (like the result of C<time()>) and as list
(like produced by c<localtime()> in list context).

Be sure to have your timezone set right, especially when this script
runs automatically.

=examples

 my $now = time;
 Mail::Message::Field->toDate($now);
 Mail::Message::Field->toDate(time);

 Mail::Message::Field->toDate(localtime);
 Mail::Message::Field->toDate;      # same
 # returns someting like:
 #     Wed, 28 Aug 2002 10:40:25 +0200

=cut

my @weekday = qw/Sun Mon Tue Wed Thu Fri Sat Sun/;
my @month   = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

sub toDate(@)
{   my $class  = shift;
    my @time   = @_== 0 ? localtime() : @_==1 ? localtime(shift) : @_;
    my $format = "$weekday[$time[6]], %d $month[$time[4]] %Y %H:%M:%S %z";
    my $time   = strftime $format, @time;

    # for C libs which do not (GNU compliantly) support %z
    $time =~ s/ (\%z|[A-Za-z ]+)$/_tz_offset($1)/e;

    $time; 
}

sub _tz_offset($)
{  my $zone = shift;
   require Time::Zone;

   my $diff = $zone eq '%z' ? Time::Zone::tz_local_offset()
           :                  Time::Zone::tz_offset($zone);
   my $minutes = int((abs($diff)+0.01) / 60);     # float rounding errors
   my $hours   = int(($minutes+0.01) / 60);
   $minutes   -= $hours * 60;
   sprintf( ($diff < 0 ? " -%02d%02d" : " +%02d%02d"), $hours, $minutes);
}

#------------------------------------------

=method addresses

Returns a list of M<Mail::Address> objects, which represent the
e-mail addresses found in this header line.

=example

 my @addr = $message->head->get('to')->addresses;
 my @addr = $message->to;

=cut

sub addresses() { Mail::Address->parse(shift->unfoldedBody) }

#------------------------------------------

=method study

Study the header field in detail: turn on the full parsing and detailed
understanding of the content of the fields.  M<Mail::Message::Field::Fast>
and M<Mail::Message::Field::Fast> objects will be transformed into any
M<Mail::Message::Field::Full> object.

=examples

 my $subject = $msg->head->get('subject')->study;
 my $subject = $msg->head->study('subject');  # same
 my $subject = $msg->study('subject');        # same

=cut

sub study()
{   my $self = shift;
    require Mail::Message::Field::Full;
    Mail::Message::Field::Full->new(scalar $self->folded);
}

#------------------------------------------

=section Other methods

=ci_method dateToTimestamp STRING

Convert a STRING which represents and RFC compliant time string into
a timestamp like is produced by the C<time> function.

=cut

sub dateToTimestamp($)
{   my $string = $_[0]->stripCFWS($_[1]);

    # in RFC822, FWSes can appear within the time.
    $string =~ s/(\d\d)\s*\:\s*(\d\d)\s*\:\s*(\d\d)/$1:$2:$3/;

    require Date::Parse;
    Date::Parse::str2time($string, 'GMT');
}


#------------------------------------------

=section Internals

=method consume $line | <$name,<$body|$objects>>

Accepts a whole field $line, or a pair with the field's $name and $body. In
the latter case, the $body data may be specified as array of $objects which
are stringified.  Returned is a nicely formatted pair of two strings: the
field's name and a folded body.

This method is called by M<new()>, and usually not by an application
program. The details about converting the $objects to a field content
are explained in L</Specifying field data>.

=warning Illegal character in field name $name
A new field is being created which does contain characters not permitted
by the RFCs.  Using this field in messages may break other e-mail clients
or transfer agents, and therefore mutulate or extinguish your message.

=cut

#=notice Empty field: $name
#Empty fields are not allowed, however sometimes found in messages constructed
#by broken applications.  You probably want to ignore this message unless you
#wrote this broken application yourself.

sub consume($;$)
{   my $self = shift;
    my ($name, $body) = defined $_[1] ? @_ : split(/\s*\:\s*/, (shift), 2);

    Mail::Reporter->log(WARNING => "Illegal character in field name $name")
       if $name =~ m/[^\041-\071\073-\176]/;

    #
    # Compose the body.
    #

    if(ref $body)                 # Objects or array
    {   my $flat = $self->stringifyData($body) or return ();
        $body = $self->fold($name, $flat);
    }
    elsif($body !~ s/\n+$/\n/g)   # Added by user...
    {   $body = $self->fold($name, $body);
    }
    else                          # Created by parser
    {   # correct erroneous wrap-seperators (dos files under UNIX)
        $body =~ s/[\012\015]+/\n/g;
        $body =~ s/^[ \t]*/ /;  # start with one blank, folding kept unchanged

        $self->log(NOTICE => "Empty field: $name")
           if $body eq " \n";
    }

    ($name, $body);
}

#------------------------------------------

=method stringifyData STRING|ARRAY|$objects

This method implements the translation of user supplied objects into
ascii fields.  The process is explained in L</Specifying field data>.

=cut

sub stringifyData($)
{  my ($self, $arg) = (shift, shift);
   my @addr;
   foreach my $obj (ref $arg eq 'ARRAY' ? @$arg : ($arg))
   {  next unless defined $obj;

      if(!ref $obj)                  { push @addr, $obj; next }
      if($obj->isa('Mail::Address')) { push @addr, $obj->format; next }

      if($obj->isa('Mail::Identity') || $obj->isa('User::Identity'))
      {   require Mail::Message::Field::Address;
          push @addr, Mail::Message::Field::Address->coerce($obj)->string;
      }
      elsif($obj->isa('User::Identity::Collection::Emails'))
      {   my @roles = $obj->roles or next;
          require Mail::Message::Field::AddrGroup;
          my $group = Mail::Message::Field::AddrGroup->coerce($obj);
          push @addr, $group->string if $group;
      }
      else
      {    # any other object is stringified
           push @addr, "$obj";
      }
   }

   @addr ? join(', ',@addr) : undef;
}

#------------------------------------------

=method setWrapLength [$length]

Force the wrapping of this field to the specified $length characters. The
wrapping is performed with M<fold()> and the results stored within
the field object.

=examples refolding the field
 $field->setWrapLength(99);

=cut

sub setWrapLength(;$)
{   my $self = shift;

    $self->foldedBody(scalar $self->fold($self->Name, $self->unfoldedBody, @_))
        if @_;

    $self;
}

#------------------------------------------

=method defaultWrapLength [$length]

Any field from any header for any message will have this default wrapping.
This is maintained in one global variable.  Without a specified $length,
the current value is returned.  The default is 78.

=cut

sub defaultWrapLength(;$)
{   my $self = shift;
    @_ ? ($default_wrap_length = shift) : $default_wrap_length;
}

#------------------------------------------

=ci_method fold $name, $body, [$maxchars]

Make the header field with $name fold into multiple lines.
Wrapping is performed by inserting newlines before a blanks in the
$body, such that no line exceeds the $maxchars and each line is as long
as possible.

The RFC requests for folding on nice spots, but this request is
mainly ignored because it would make folding too slow.

=cut

sub fold($$;$)
{   my $thing = shift;
    my $name  = shift;
    my $line  = shift;
    my $wrap  = shift || $default_wrap_length;
    defined $line or $line = '';

    $line    =~ s/\n\s/ /gms;            # Remove accidental folding
    return " \n" unless CORE::length($line);  # empty field

    my @folded;
    while(1)
    {  my $max = $wrap - (@folded ? 1 : CORE::length($name) + 2);
       my $min = $max >> 2;
       last if CORE::length($line) < $max;

          $line =~ s/^ ( .{$min,$max}   # $max to 30 chars
                        [;,]            # followed at a ; or ,
                       )[ \t]           # and then a WSP
                    //x
       || $line =~ s/^ ( .{$min,$max} ) # $max to 30 chars
                       [ \t]            # followed by a WSP
                    //x
       || $line =~ s/^ ( .{$max,}? )    # longer, but minimal chars
                       [ \t]            # followed by a WSP
                    //x
       || $line =~ s/^ (.*) //x;        # everything

       push @folded, " $1\n";
    }

    push @folded, " $line\n" if CORE::length($line);
    wantarray ? @folded : join('', @folded);
}

=method unfold STRING
The reverse action of M<fold()>: all lines which form the body of a field
are joined into one by removing all line terminators (even the last).
Possible leading blanks on the first line are removed as well.

=cut

sub unfold($)
{   my $string = $_[1];
    for($string)
    {   s/\r?\n//gm;
        s/^ +//;
    }
    $string;
}

#------------------------------------------

=section Error handling

=chapter DETAILS

=section Field syntax

Fields are stored in the header of a message, which are represented by
M<Mail::Message::Head> objects. A field is a combination of a I<name>,
I<body>, and I<attributes>.  Especially the term "body" is cause for
confusion: sometimes the attributes are considered to be part of the body.

The name of the field is followed by a colon ("C<:>", not preceded by
blanks, but followed by one blank).  Each attribute is preceded by
a separate semi-colon ("C<;>").  Names of fields are case-insensitive and
cannot contain blanks.

=examples of fields

Correct fields:

 Field: hi!
 Content-Type: text/html; charset=latin1
 
Incorrect fields, but accepted:

 Field : wrong, blank before colon
 Field:                 # wrong, empty
 Field:not nice, blank preferred after colon
 One Two: wrong, blank in name

=subsection Folding fields

Fields which are long can be folded to span more than one line.  The real
limit for lines in messages is only at 998 characters, however such long
lines are not easy to read without support of an application.  Therefore
rfc2822 (which defines the message syntax) specifies explicitly that
field lines can be re-formatted into multiple sorter lines without change
of meaning, by adding new-line characters to any field before any blank or
tab.

Usually, the lines are reformatted to create lines which are 78 characters
maximum. Some applications try harder to fold on nice spots, like before
attributes.  Especially the C<Received> field is often manually folded into
some nice layout.  In most cases however, it is preferred to produce lines
which are as long as possible but max 78.

BE WARNED that all fields can be subjected to folding, and that you usually
want the unfolded value.

=examples of field folding

 Subject: this is a short line, and not folded

 Subject: this subject field is much longer, and therefore
  folded into multiple
  lines, although one more than needed.

=subsection Structured fields

The rfc2822 describes a large number of header fields explicitly.  These
fields have a defined meaning.  For some of the fields, like the C<Subject>
field, the meaning is straight forward the contents itself.  These fields
are the I<Unstructured Fields>.

Other fields have a well defined internal syntax because their content is
needed by e-mail applications. For instance, the C<To> field contains
addresses which must be understood by all applications in the same way.
These are the I<Structured Fields>, see M<isStructured()>.

=subsection Comments in fields

Stuctured fields can contain comments, which are pieces of text enclosed in
parenthesis.  These comments can be placed close to anywhere in the line
and must be ignored be the application.  Not all applications are capable
of handling comments correctly in all circumstances.

=examples of field comments

 To: mailbox (Mail::Box mailinglist) <mailbox@overmeer.net>
 Date: Thu, 13 Sep 2001 09:40:48 +0200 (CEST)
 Subject: goodbye (was: hi!)

On the first line, the text "Mail::Box mailinglist" is used as comment.
Be warned that rfc2822 explicitly states that comments in e-mail address
specifications should not be considered to contain any usable information.

On the second line, the timezone is specified as comment. The C<Date>
field format has no way to indicate the timezone of the sender, but only
contains the timezone difference to UTC, however one could decide to add
this as comment.  Application must ignore this data because the C<Date>
field is structured.

The last field is unstructured.  The text between parantheses is an
integral part of the subject line.

=section Getting a field

As many programs as there are handling e-mail, as many variations on
accessing the header information are requested.  Be careful which way
you access the data: read the variations described here and decide
which solution suites your needs best.

=subsection Using get() field

The C<get()> interface is copied from other Perl modules which can
handle e-mail messages.  Many applications which simply replace
M<Mail::Internet> objects by M<Mail::Message> objects will work
without modification.

There is more than one get method.  The exact results depend on which
get you use.  When M<Mail::Message::get()> is called, you will get the
unfolded, stripped from comments, stripped from attributes contents of
the field as B<string>.  Character-set encodings will still be in the
string.  If the same fieldname appears more than once in the header,
only the last value is returned.

When M<Mail::Message::Head::get()> is called in scalar context, the
last field with the specified name is returned as field B<object>.
This object strinigfies into the unfolded contents of the field, including
attributes and comments.  In list context, all appearances of the field
in the header are returned as objects.

BE WARNED that some lines seem unique, but are not according to the
official rfc.  For instance, C<To> fields can appear more than once.
If your program calls C<get('to')> in scalar context, some information
is lost.

=examples of using get()

 print $msg->get('subject') || 'no subject';
 print $msg->head->get('subject') || 'no subject';

 my @to = $msg->head->get('to');

=subsection Using study() field

As the name C<study> already implies, this way of accessing the fields is
much more thorough but also slower.  The C<study> of a field is like a
C<get>, but provides easy access to the content of the field and handles
character-set decoding correctly.

The M<Mail::Message::study()> method will only return the last field
with that name as object.  M<Mail::Message::Head::study()> and
M<Mail::Message::Field::study()> return all fields when used in list
context.

=examples of using study()

 print $msg->study('subject') || 'no subject';
 my @rec  = $msg->head->study('Received');

 my $from = $msg->head->get('From')->study;
 my $from = $msg->head->study('From');  # same
 my @addr = $from->addresses;

=subsection Using resent groups

Some fields belong together in a group of fields.  For instance, a set
of lines is used to define one step in the mail transport process.  Each
step adds a C<Received> line, and optionally some C<Resent-*> lines and
C<Return-Path>.  These groups of lines shall stay together and in order
when the message header is processed.

The C<Mail::Message::Head::ResentGroup> object simplifies the access to
these related fields.  These resent groups can be deleted as a whole,
or correctly constructed.

=examples of using resent groups

 my $rgs = $msg->head->resentGroups;
 $rgs[0]->delete if @rgs;

 $msg->head->removeResentGroups;

=section The field's data

There are many ways to get the fields info as object, and there are also
many ways to process this data within the field.

=subsection Access to the field

=over 4

=item * M<string()>

Returns the text of the body exactly as will be printed to file when
M<print()> is called, so name, main body, and attributes.

=item * M<foldedBody()>

Returns the text of the body, like M<string()>, but without the name of
the field.

=item * M<unfoldedBody()>

Returns the text of the body, like M<foldedBody()>, but then with all
new-lines removed.  This is the normal way to get the content of
unstructured fields.  Character-set encodings will still be in place.
Fields are stringified into their unfolded representation.

=item * M<stripCFWS()>

Returns the text of structured fields, where new-lines and comments are
removed from the string.  This is a good start for parsing the field,
for instance to find e-mail addresses in them.

=item * M<Mail::Message::Field::Full::decodedBody()>

Studied fields can produce the unfolded text decoded into utf8 strings.
This is an expensive process, but the only correct way to get the field's
data.  More useful for people who are not living in ASCII space.

=item * Studied fields

Studied fields have powerful methods to provide ways to access and produce
the contents of (structured) fields exactly as the involved rfcs prescribe.

=back

=subsection Using simplified field access

Some fields are accessed that often that there are support methods to
provide simplified access.  All these methods are called upon a message
directly.

=examples of simplified field access

 print $message->subject;
 print $message->get('subject') || '';  # same

 my @from = $message->from; # returns addresses
 $message->reply->send if $message->sender;

The C<sender> method will return the address specified in the C<Sender>
field, or the first named in the C<From> field.  It will return C<undef>
in case no address is known.

=subsection Specifying field data

Field data can be anything, strongly dependent on the type
of field at hand. If you decide to contruct the fields very
carefully via some M<Mail::Message::Field::Full> extension (like via
M<Mail::Message::Field::Addresses> objects), then you will have protection
build-in.  However, you can bluntly create any M<Mail::Message::Field>
object based on some data.

When you create a field, you may specify a string, object, or an array
of strings and objects.  On the moment, objects are only used to help
the construction on e-mail addresses, however you may add some of your
own.

The following rules (implemented in M<stringifyData()>) are obeyed given
the argument is:

=over 4
=item * a string
The string must be following the (complicated) rules of the rfc2822, and
is made field content as specified.  When the string is not terminated
by a new-line (C<"\n">) it will be folded according to the standard rules.

=item * a M<Mail::Address> object
The most used Perl object to parse and produce address lines.  This object
does not understand character set encodings in phrases.

=item * a M<Mail::Identity> object
As part of the M<User::Identity> distribution, this object has full
understanding of the meaning of one e-mail address, related to a person.
All features defined by rfc2822 are implemented.

=item * a M<User::Identity> object
A person is specified, which may have more than one M<Mail::Identity>'s
defined.  Some methods, like M<Mail::Message::reply()> and
M<Mail::Message::forward()> try to select the right e-mail address
smart (see their method descriptions), but in other cases the first
e-mail address found is used.

=item * a M<User::Identity::Collection::Emails> object
All M<Mail::Identity> objects in the collection will be included in
the field as a group carying the name of the collection.

=item * any other object
For all other objects, the stringification overload is used to produce
the field content.

=item * an ARRAY
You may also specify an array with a mixture of any of the above.  The
elements will be joined as comma-separated list.  If you do not want
comma's inbetween, you will have to process the array yourself.

=back

=examples specifying simple field data

 my $f = Mail::Message::Field->new(Subject => 'hi!');
 my $b = Mail::Message->build(Subject => 'monkey');

=exampless specifying e-mail addresses for a field

 use Mail::Address;
 my $fish = Mail::Address->new('Mail::Box', 'fish@tux.aq');
 print $fish->format;   # ==> Mail::Box <fish@tux.aq>
 my $exa  = Mail::Address->new(undef, 'me@example.com');
 print $exa->format;    # ==> me@example.com

 my $b = $msg->build(To => "you@example.com");
 my $b = $msg->build(To => $fish);
 my $b = $msg->build(To => [ $fish, $exa ]);

 my @all = ($fish, "you@example.com", $exa);
 my $b = $msg->build(To => \@all);
 my $b = $msg->build(To => [ "xyz", @all ]);

=examples specifying identities for a field

 use User::Identity;
 my $patrik = User::Identity->new
  ( name      => 'patrik'
  , full_name => "Patrik Fältström"  # from rfc
  , charset   => "ISO-8859-1"
  );
 $patrik->add
  ( email    => "him@home.net"
  );

 my $b = $msg->build(To => $patrik);

 $b->get('To')->print;
   # ==> =?ISO-8859-1?Q?Patrik_F=E4ltstr=F6m?=
   #     <him@home.net>

=section Field class implementation

For performance reasons only, there are three types of fields: the
fast, the flexible, and the full understander:

=over 4

=item * M<Mail::Message::Field::Fast>

C<Fast> objects are not derived from a C<Mail::Reporter>.  The consideration
is that fields are so often created, and such a small objects at the same
time, that setting-up a logging for each of the objects is relatively
expensive and not really useful.
The fast field implementation uses an array to store the data: that
will be faster than using a hash.  Fast fields are not easily inheritable,
because the object creation and initiation is merged into one method.

=item * M<Mail::Message::Field::Flex>

The flexible implementation uses a hash to store the data.  The M<new()>
and C<init> methods are split, so this object is extensible.

=item * M<Mail::Message::Field::Full>

With a full implementation of all applicable RFCs (about 5), the best
understanding of the fields is reached.  However, this comes with
a serious memory and performance penalty.  These objects are created
from fast or flex header fields when M<study()> is called.

=back

=cut

1;
