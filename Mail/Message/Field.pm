use strict;
use warnings;

package Mail::Message::Field;
use base 'Mail::Reporter';

use Carp;
use Mail::Address;
use Date::Parse;

our %_structured;  # not to be used directly: call isStructured!
my $default_wrap_length = 78;

use overload qq("") => sub { $_[0]->unfoldedBody }
           , '+0'   => 'toInt'
           , bool   => sub {1}
           , cmp    => sub { $_[0]->unfoldedBody cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;


=head1 NAME

Mail::Message::Field - one line of a message header

=head1 SYNOPSIS

 my $field = Mail::Message::Field->new(From => 'me@example.com');
 print $field->name;
 print $field->body;
 print $field->comment;
 print $field->content;  # body & comment
 $field->print(\*OUT);
 print $field->string;
 print "$field\n";
 print $field->attribute('charset') || 'us-ascii';

=head1 DESCRIPTION

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

=head2 Header Fields

This implementation follows the guidelines of rfc2822 as close as possible,
and may there produce a different output than implementations based on
the obsolete rfc822.  However, the old output will still be accepted.

A head line is composed of two parts separated by a color (C<:>).  Before
the colon is called the I<name> of the field, and the right part the
I<body>.  In some lines, the body contains a semicolon (C<;>) which
indicates the start of something refered to as I<comment>.  This comment
is often used to contain I<attributes>: key-value pairs of information,
which is of course much more important than simply accompanying text.

=head2 folding

Many implementations of mail transfer agents (MTAs) have problems with
lines longer than 998 characters.  Many implementations of mail user agents
(MUAs) can not handle lines longer than 78 characters well.  MTAs are
programs which implement the SMTP protocol, like the C<sendmail> command
or a web-browser which sends e-mail.  MUAs are programs which people use to
read their e-mail, like C<mutt>, C<elm>, C<pine>, or also a web-browser.

To avoid the problems with long lines, head lines are often folded into
lines of 78 characters maximum.  Longer lines are wrapped, in RFC-terms
I<folded>.  On some places in the body of a field, a line-feed is
inserted.  The remaining part of the body is on the next line, which
MUST be preceeded by at least one white-space (tab or blank)

Some fields are called C<structured>: their structure is well-defined by
the RFC.  In these fields, their is more flexibility where folding may
take place.  Other fields only permit folding on white-spaces.

=head2 consideration

Mail::Message::Field is the only object in the Mail::Box suite
which is not derived from a Mail::Reporter.  The consideration is
that fields are so often created, and such a small objects at the
same time, that setting-up a logging for each of the objects is relatively
expensive and not really useful.

For the same reason, the are two types of fields: the flexible and
the fast:

=over 4

=item * Mail::Message::Field::Flex

The flexible implementation uses a has to store the data.  The new()
and C<init> are split, so this object is extensible.

=item * Mail::Message::Field::Fast

The fast implementation uses an array to store the same data.  That
will be faster.  Furthermore, it is less extensible because the object
creation and initiation is merged into one method.

=back

As user of the object, there is not visible difference.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new DATA

See Mail::Message::Field::Fast::new() or Mail::Message::Field::Flex::new().
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

#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

=method clone

Create a copy of this field object.

=cut

#------------------------------------------

=method length

Returns the total length of the field in characters, which includes the
field's name, body and folding characters.

=cut

#------------------------------------------

=method isStructured

(object method or class method)

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
     Content-Length Content-Type
     Delivered-To
     Lines
     MIME-Version
     Precedence
     Status/;
} 

sub isStructured(;$)
{   my $name  = ref $_[0] ? shift->name : $_[1];
    exists $_structured{lc $name};
}

#------------------------------------------

=head2 Access to the Field

=cut

#------------------------------------------

=method name

Returns the name of this field, with all characters lower-cased for
ease of comparison.  See Name() as well.

=cut

#------------------------------------------

=method Name

Returns the name of this field in original casing.  See name() as well.

=cut

#------------------------------------------

=method wellformedName [STRING]

(Instance method class method)
As instance method, the current field's name is correctly formatted
and returned.  When a STRING is used, that one is formatted.

=examples

 print Mail::Message::Field->Name('content-type') # Content-Type

 my $field = $head->get('date');
 print $field->Name;                              # Date

=cut

# attempt to change the case of a tag to that required by RFC822. That
# being all characters are lowercase except the first of each
# word. Also if the word is an `acronym' then all characters are
# uppercase. We, rather arbitrarily, decide that a word is an acronym
# if it does not contain a vowel and isn't the well-known 'Cc' or
# 'Bcc' headers.

my %wf_lookup
  = qw/mime MIME  ldap LDAP  soap SOAP
       bcc Bcc  cc Cc/;

sub wellformedName(;$)
{   my $thing = shift;
    my $name = @_ ? shift : $thing->name;

    join '-',
       map { $wf_lookup{lc $_} || ( /[aeiouyAEIOUY]/ ? ucfirst lc : uc ) }
          split /\-/, $name;
}

#------------------------------------------

=method folded

Returns the folded version of the whole header.  When the header is shorter
than the wrap length, a list of one line is returned.  Otherwise more
lines will be returned, all but the first starting with at least one blank.
See also foldedBody() to get the same information without the field's name.

In scalar context, the lines are delived into one string, which is
faster because that's the way they are stored...

=examples

 my @lines = $field->folded;
 print $field->folded;
 print scalar $field->folded; # faster

=cut

#------------------------------------------

=method body

Returns the body of the field.  When this field is structured, it will
be B<stripped> from everything what is behind the first semi-color (C<;>).
In aby case, the string is unfolded.  

Whether the field is structured is defined by isStructured().
This method may be what you want, but usually, the foldedBody() and
unfoldedBody() are what you are looking for.

=cut

sub body()
{   my $self = shift;
    my $body = $self->unfoldedBody;
    return $body unless $self->isStructured;

    $body =~ s/\s*\;.*//s;
    $body;
}

#------------------------------------------

=method foldedBody [BODY]

Returns the body as a set of lines. In scalar context, this will be one line
containing newlines.  Be warned about the newlines when you do
pattern-matching on the result of thie method.

The optional BODY argument changes the field's body.  The folding of the
argument must be correct.

=cut

#------------------------------------------

=method unfoldedBody [BODY, [WRAP]]

Returns the body as one single line, where all folding information (if
available) is removed.  This line will also NOT end on a new-line.

The optional BODY argument changes the field's body.  The right folding is
performed before assignment.  The WRAP may be specified to enforce a
folding size.

=examples

 my $body = $field->unfoldedBody;
 print "$field";   # via overloading

=cut

#------------------------------------------

=method comment [STRING]

Returns the unfolded comment (part after a semi-colon) in a structureed
header-line. optionally after setting it to a new STRING first.
When C<undef> is specified as STRING, the comment is removed.
Whether the field is structured is defined by isStructured().

The I<comment> part of a header field often contains C<attributes>.  Often
it is preferred to use attributes() on them.

=cut

sub comment(;$)
{   my $self = shift;
    return undef unless $self->isStructured;

    my $body = $self->unfoldedBody;

    if(@_)
    {   my $comment = shift;
        $body    =~ s/\s*\;.*//;
        $body   .= "; $comment" if defined $comment && length $comment;
        $self->unfoldedBody($body);
        return $comment;
    }
 
    $body =~ s/.*?\;\s*// ? $body : '';
}

#------------------------------------------

sub content() { shift->unfoldedBody }  # Compatibility

#------------------------------------------

=method attribute NAME [, VALUE]

Get the value of an attribute, optionally after setting it to a new value.
Attributes are part of some header lines, and hide themselves in the
comment field.  If the attribute does not exist, then C<undef> is
returned.

=examples

 my $field = Mail::Message::Field->new(
    'Content-Type: text/plain; charset="us-ascii"');

 print $field->attribute('charset');        # --> us-ascii
 print $field->attribute('bitmap') || 'no'  # --> no
 $field->atrribute(filename => '/tmp/xyz'); # sets field

=cut

sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $body  = $self->unfoldedBody;

    unless(@_)
    {   return
           $body =~ m/\b$attr=( "( (?: [^"]|\\" )* )"
                              | '( (?: [^']|\\' )* )'
                              | (\S*)
                              )
                  /xi ? $+ : undef;
    }

    my $value = shift;
    unless(defined $value)  # remove attribute
    {   for($body)
        {      s/\b$attr='([^']|\\')*'//i
            or s/\b$attr="([^"]|\\")*"//i
            or s/\b$attr=\S*//i;
        }
        $self->unfoldedBody($body);
        return undef;
    }

    (my $quoted = $value) =~ s/"/\\"/g;
    for($body)
    {       s/\b$attr='([^']|\\')*'/$attr="$quoted"/i
         or s/\b$attr="([^"]|\\")*"/$attr="$quoted"/i
         or s/\b$attr=\S+/$attr="$quoted"/i
         or do { $_ .= qq(; $attr="$quoted") }
    }

    $self->unfoldedBody($body);
    $value;
}

#------------------------------------------

=method print [FILEHANDLE]

Print the whole header-line to the specified file-handle. One line may
result in more than one printed line, because of the folding of long
lines.  The FILEHANDLE defaults to the selected handle.

=cut

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print($self->folded);
}

#------------------------------------------

=method string [WRAP]

Returns the field as string.  By default, this returns the same as
folded(). However, the optional WRAP will cause to re-fold to take
place (without changing the folding stored inside the field).

=cut

sub toString(;$) {my $self = shift;$self->string(@_)}
sub string(;$)
{   my $self  = shift;
    return $self->folded unless @_;

    my $wrap  = shift || $default_wrap_length;
    my $name  = $self->Name;
    my @lines = $self->fold($name, $self->unfoldedBody, $wrap);
    $lines[0] = $name . ':' . $lines[0];
    wantarray ? @lines : join('', @lines);
}

#------------------------------------------

=method toInt

Returns the value which is related to this field as integer.  A check is
performed whether this is right.

=cut

sub toInt()
{   my $self = shift;
    return $1 if $self->body =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not numerical: ". $self->toString);

    return undef;
}

#------------------------------------------

=method toDate [TIME]

(Class method) Convert a timestamp into a MIME-acceptable date format.  This
differs from the default output of C<localtime> in scalar context.  Without
argument, the C<localtime> is used to get the current time.  Be sure to have
your timezone set right, especially when this script runs automatically.

=examples

 my $now = localtime;
 Mail::Message::Field->toDate($now);

 Mail::Message::Field->toDate(scalar localtime);
 Mail::Message::Field->toDate;  # same
 # returns someting like:  Wed, 28 Aug 2002 10:40:25 +0200

=cut

sub toDate($)
{   my $class = shift;
    use POSIX 'strftime';
    my @time  = @_ ? localtime(shift) : localtime;
    strftime "%a, %d %b %Y %H:%M:%S %z", @time;
}

#------------------------------------------

=method stripCFWS [STRING]

(Class or Instance method) Remove the I<comments> and I<folding white
spaces> from the STRING.  Without string and only as instance method, the
unfoldedBody() is being stripped and returned.

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

           if(length $r && substr($r, -1) eq "\\") { $r .= $s } # escaped special
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

=method dateToTimestamp STRING

(Class method)
Convert a STRING which represents and RFC compliant time string into
a timestamp like is produced by the C<time> function.

=cut

sub dateToTimestamp($)
{   my $string = $_[0]->stripCFWS($_[1]);

    # in RFC822, FWSes can appear within the time.
    $string =~ s/(\d\d)\s*\:\s*(\d\d)\s*\:\s*(\d\d)/$1:$2:$3/;

    str2time($string, 'GMT');
}

#------------------------------------------

=method addresses

Returns a list of Mail::Address objects, which represent the
e-mail addresses found in this header line.

=example

 my @addr = $message->head->get('to')->addresses;
 my @addr = $message->to;

=cut

sub addresses() { Mail::Address->parse(shift->body) }

#------------------------------------------

=method nrLines

Returns the number of lines needed to display this header-line.

=cut

sub nrLines() { my @l = shift->foldedBody; scalar @l }

#------------------------------------------

=method size

Returns the number of bytes needed to display this header-line.

=cut

sub size() {length shift->toString}

#------------------------------------------

=method toDisclose

Returns whether this field can be disclosed to other people, for instance
when sending the message to an other party.  Returns a C<true> or C<false>
condition.
See also Mail::Message::printUndisclosed()

=cut

sub toDisclose()
{   shift->name !~ m!^(?: (?:x-)?status
                      |   (?:resent-)?bcc
                      |   Content-Length
                      |   x-spam-
                      ) $!x;
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method consume LINE | (NAME,BODY|OBJECTS)

(Class method)
Accepts a whole field LINE, or a pair with the field's NAME and BODY. In
the latter case, the BODY data may be specified as array of OBJECTS which
are stringified.  Returned is a nicely formatted pair of two strings: the
field's name and a folded body.

This method is called by new(), and usually not be an application
program.

=cut

sub consume($;$)
{   my $self = shift;
    my ($name, $body) = defined $_[1] ? @_ : split(/\s*\:\s*/, (shift), 2);

    Mail::Reporter->log(WARNING => "Illegal character in field name: $name")
       if $name =~ m/[^\041-\071\073-\176]/;

    #
    # Compose the body.
    #

    if(ref $body)                 # Objects
    {   my @objs = ref $body eq 'ARRAY' ? @$body
                 : defined $body        ? ($body)
                 :                        ();

        # Skip field when no objects are specified.
        return () unless @objs;

        # Format the addresses
        my @addrs = map {ref $_ && $_->isa('Mail::Address') ? $_->format : "$_"}             @objs;

        $body = $self->fold($name, join(', ', @addrs));
    }
    elsif($body !~ s/\n+$/\n/g)   # Added by user...
    {   $body = $self->fold($name, $body);
    }
    else                          # Created by parser
    {   # correct erroneous wrap-seperators (dos files under UNIX)
        $body =~ s/[\012\015]+/\n/g;
        $body =~ s/^\s*/ /;  # start with one blank, folding kept unchanged

        if($body eq "\n")
        {   Mail::Reporter->log(WARNING => "Empty field: $name\n");
            return ();
        }
    }

    ($name, $body);
}

#------------------------------------------

=method setWrapLength [LENGTH]

Force the wrapping of this field to the specified LENGTH characters. The
wrapping is performed with fold() and the results stored within
the field object.

Even without LENGTH this method is useful: the default wrap length will
be enforced (re-folding will take place).

=examples

 $field->setWrapLength(99);
 $field->setWrapLength;

=cut

sub setWrapLength(;$)
{   my $self = shift;
    $self->[1] = $self->fold($self->[0],$self->unfoldedBody, @_);
}

#------------------------------------------

=method defaultWrapLength [LENGTH]

Any field from any header for any message will have this default wrapping.
This is maintained in one global variable.  Without a specified LENGTH,
the current value is returned.  The default is 78.

=cut

sub defaultWrapLength(;$)
{   my $self = shift;
    @_ ? ($default_wrap_length = shift) : $default_wrap_length;
}

#------------------------------------------

=method fold NAME, BODY, [MAXCHARS]

Make the header field with NAME fold into multiple lines.
Wrapping is performed by inserting newlines before a blanks in the
BODY, such that no line exceeds the MAXCHARS and each line is as long
as possible.

The RFC requests for folding on nice spots, but this request is
mainly ignored because it would make folding too slow.

=cut

sub fold($$;$)
{   my $self = shift;
    my $name = shift;
    my $line = shift;
    my $wrap = shift || $default_wrap_length;

    $line    =~ s/\ns*/ /gms;            # Remove accidental folding
    return " \n" unless length $line;    # empty field

    my @folded;
    while(1)
    {  my $max = $wrap - (@folded ? 1 : length($name) + 2);
       my $min = $max >> 2;
       last if length $line < $max;

          $line =~ s/^ ( .{$min,$max}   # $max to 30 chars
                        [;,]            # followed by a; or ,
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

    push @folded, " $line\n" if length $line;
    wantarray ? @folded : join('', @folded);
}

#------------------------------------------

=method unfold STRING

The reverse of fold(): all lines which form the body of a field are
joined into one by removing all line terminators (even the last).
Possible leading blanks on the first line are removed as well.

=cut

sub unfold($)
{   my $string = $_[1];
    for($string)
    {   s/\n//g;
        s/^ +//;
    }
    $string;
}

#------------------------------------------

1;
