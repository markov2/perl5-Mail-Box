use strict;
use warnings;

# This package defines the only object in Mail::Box which is not
# derived from Mail::Reporter.  See the manual page.

package Mail::Message::Field;
use Mail::Box::Parser;

use Carp;
use Mail::Address;

our $VERSION = 2.016;
our %_structured;  # not to be used directly: call isStructured!

use overload qq("") => sub { $_[0]->body }
           , '+0'   => 'toInt'
           , bool   => sub {1}
           , cmp    => sub { $_[0]->body cmp "$_[1]" }
           , '<=>'  => sub { $_[2]
                           ? $_[1]        <=> $_[0]->toInt
                           : $_[0]->toInt <=> $_[1]
                           }
           , fallback => 1;


=head1 NAME

Mail::Message::Field - one line of a message header

=head1 CLASS HIERARCHY

 Mail::Message::Field
 is a Mail::Reporter

=head1 SYNOPSIS

 my $field = Mail::Message::Field->new(From => 'me@example.com');
 print $field->name;
 print $field->body;
 print $field->comment;
 print $field->content;  # body & comment
 $field->print(\*OUT);
 print $field->toString;
 print "$field\n";
 print $field->attribute('charset') || 'us-ascii';

=head1 DESCRIPTION

These objects each store one header line, and facilitates access routines to
the information hidden in it.  Also, you may want to have a look at the
added methods of a message:

 my $from    = $message->from;
 my $subject = $message->subject;
 my $msgid   = $message->messageId;

 my @to      = $message->to;
 my @cc      = $message->cc;
 my @bcc     = $message->bcc;
 my @dest    = $message->destinations;

 my $other   = $message->get('Reply-To');

=head2 consideration

C<Mail::Message::Field> is the only object in the C<Mail::Box> suite
which is not derived from a C<Mail::Reporter>.  The consideration is
that fields are so often created, and such a small objects at the
same time, that setting-up a logging for each of the objects is relatively
expensive and not really useful.

For the same reason, the are two types of fields: the flexible and
the fast:

=over 4

=item C<Mail::Message::Field::Flex>

The flexible implementation uses a has to store the data.  The C<new>
and C<init> are split, so this object is extendible.

=item C<Mail::Message::Field::Fast>

The fast implementation uses an array to store the same data.  That
will be faster.  Furthermore, it is less extendible because the object
creation and initiation is merged into one method.

=back

As user of the object, there is not visible difference.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Field> objects:

      addresses                            new ...
      attribute NAME [, VALUE]             print [FILEHANDLE]
      body                                 toDate TIME
      comment [STRING]                     toInt
      content                              toString
      folded [ARRAY-OF-LINES]              wellformedName ...
      name

The extra methods for extension writers:

      clone                                nrLines
      isStructured                         setWrapLength CHARS
      newNoCheck NAME, BODY, COMM...       size

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new LINE [,ARRAY-OF-OPTIONS]

=item new NAME, BODY [,COMMENT [, OPTIONS]]

=item new NAME, OBJECT|ARRAY-OF-OBJECTS [,COMMENT [, OPTIONS]]

Create a new header-object.  Specify the whole header-LINE at once, and
it will be split-up for you.  I case you already have the parts of the
header-line, you may specify them.

In structured fields (a list of pre-defined fields are considered
to have a well-described format, checked with the C<isStructured> method)
everything behind a semi-color is officially a COMMENT.  The comment is
often (ab)used to supply extra information about the body information.
When the field you specify is structured, and you do not specify a comment
yourself, it will be stripped from the LINE or BODY for you.

To keep the communication overlead low (there are too many of these
field-objects to be created), the OPTIONS may be specified as last
argument to C<new>, but as reference to an array.  There are no
options defined yet, but they may appear in the future.

In case you specify a single OBJECT, or a reference to an array of OBJECTS,
these objects are processed to become suitable to fill a field.  When
you specify one or more C<Mail::Address> objects, these are tranformed
into a string using their C<format> method.

You may also add one C<Mail::Message::Field>, which body is taken.  For other
objects, stringification is tried.  In case of an array, the elements are
joined with a comma.

Examples:

   my @options = (log => 'NOTICE', trace => 'NONE');
   my $mime = Mail::Message::Field->new(
       'Content-Type: text/plain; charset=US-ASCII', \@options);

   my $mime = Mail::Message::Field->new(
       'Content-Type' => 'text/plain; charset=US-ASCII');

   my $mime = Mail::Message::Field->new(
       'Content-Type' => 'text/plain', 'charset=US-ASCII');

   my $mime = Mail::Message::Field->new(
       To => Mail::Address->new('my name', 'me@example.com');

   my $mime = Mail::Message::Field->new(
       Cc => [ Mail::Address->new('your name', 'you@example.com')
             , Mail::Address->new('his name', 'he@example.com')
             ]);

But, more often, you would call

   my $head = Mail::Message::Head->new;
   $head->add('Content-Type' => 'text/plain; charset=US-ASCII');

which implicitly calls this constructor (when needed).  You can specify
the same things for C<add> as this C<new> accepts.

=cut

sub new(@)
{   shift;
    require Mail::Message::Field::Fast;
    Mail::Message::Field::Fast->new(@_);
}

#------------------------------------------

=item name

Returns the name of this field, with all characters lower-cased for
ease of comparison.

=cut

#------------------------------------------

=item wellformedName

=item wellformedName [STRING]

(Instance method class method)
As instance method, the current field's name is correctly formatted
and returned.  When a STRING is used, that one is formatted.

Examples:

 print Mail::Message::Field->Name('content-type') # Content-Type

 my $field = $head->get('date');
 print $field->Name;                              # Date

=cut

sub wellformedName(;$)
{   my $thing = shift;
    my $name = @_ ? shift : $thing->name;
    $name =~ s/(\w+)/\L\u$1/g;
    $name;
}

#------------------------------------------

=item body

Returns the body of the field, unmodified but stripped from comment
and CR LF characters (as far as were present at creation).

=cut

#------------------------------------------

=item comment [STRING]

Returns the comment (part after a semi-colon) in the header-line,
optionally after setting it to a new value first.

=cut

#------------------------------------------

=item content

Returns the body and comment part of the field, separated by
a semi-colon.

=cut

sub content()
{   my $self    = shift;
    my $comment = $self->comment;
    $self->body . ($comment ? "; $comment" : '');
}

#------------------------------------------

=item folded [ARRAY-OF-LINES]

Returns the folded version of the header.  When the header is shorter
than the wrap length, a list of one line is returned.  Otherwise more
lines will be returned, all but the first starting with a blank.

=cut

#------------------------------------------

=item attribute NAME [, VALUE]

Get the value of an attribute, optionally after setting it to a new value.
Attributes are part of some header lines, and hide themselves in the
comment field.  If the attribute does not exist, then C<undef> is
returned.  For instance

 my $field = Mail::Message::Field->new(
    'Content-Type: text/plain; charset="us-ascii"');
 print $field->attribute('charset');        # --> us-ascii
 print $field->attribute('bitmap') || 'no'  # --> no

=cut

sub attribute($;$)
{   my ($self, $name) = (shift, shift);

    if(@_ && defined $_[0])
    {   my $value   = shift;
        my $comment = $self->comment;
        if(defined $comment)
        {   unless($comment =~ s/\b$name=(['"]?)[^'"]*\1/$name=$1$value$1/i )
            {   $comment .= qq(; $name="$value");
            }
        }
        else { $comment = qq($name="$value") }

        $self->comment($comment);
        $self->setWrapLength(72);
        return $value;
    }

    my $comment = $self->comment or return;
    $comment =~ m/\b$name=(['"]?)([^'"]*)\1/i ;
    $2;
}

#------------------------------------------

=item print [FILEHANDLE]

Print the whole header-line to the specified file-handle. One line may
result in more than one printed line, because of the folding of long
lines.  The FILEHANDLE defaults to the selected handle.

=cut

sub print($)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print($self->folded);
}

#------------------------------------------

=item toString

Returns the whole header-line.

Example:

    my @lines = $field->toString;
    print $field->toString;
    print "$field";

=cut

sub toString()
{   my @folded = shift->folded;
    wantarray ? @folded : join('', @folded);
}

#------------------------------------------

=item toInt

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

=item toDate TIME

(Class method) Convert a timestamp into a MIME-acceptable date format.

Example:

 Mail::Message::Field->toDate(localtime);

=cut

sub toDate($)
{   my ($class, @time) = @_;
    use POSIX 'strftime';
    strftime "%a, %d %b %Y %H:%M:%S %z", @time;
}

#------------------------------------------

=item addresses

Returns a list of C<Mail::Address> objects, which represent the
e-mail addresses found in this header line.

Example:

 my @addr = $message->head->get('to')->addresses;
 my @addr = $message->to;

=cut

sub addresses() { Mail::Address->parse(shift->body) }

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item clone

Create a copy of this field object.

=cut

#------------------------------------------

=item isStructured

(object method or class method)

Examples:

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

=item nrLines

Returns the number of lines needed to display this header-line.

=cut

sub nrLines() { my @l = shift->folded; scalar @l }

#------------------------------------------

=item size

Returns the number of bytes needed to display this header-line.

=cut

sub size() {length shift->toString}

#------------------------------------------

=item setWrapLength CHARS

Make the header fold before the specified number of CHARS on a line.  This
will be ignored for un-structured headers.

=cut

sub setWrapLength($)
{   my $self = shift;
    return $self unless $self->isStructured;

    my $wrap = shift;
    my $line = $self->toString;

    $self->folded
      ( length $line < $wrap ? undef
      : Mail::Box::Parser->defaultParserType->foldHeaderLine($line, $wrap)
      );

    $self;
}

#------------------------------------------

=item newNoCheck NAME, BODY, COMMENT, [FOLDED]

(Class method)
Do not use this yourself.  This created an object without checking, which
is ok when the parser is doing that already.  However, if you add unchecked
fields you may get into big trouble!

=cut

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

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
