use strict;
use warnings;

package Mail::Message::Field::Unstructured;
use base 'Mail::Message::Field::Full';

=chapter NAME

Mail::Message::Field::Unstructured - unstructured "Full" field

=chapter SYNOPSIS

 !! UNDER CONSTRUCTION !!
 my $f = Mail::Message::Field::Unstructured->new(Comments => 'hi!');

=chapter DESCRIPTION

Unstructured fields do contain information which is not restricted in
any way.  RFC2822 defines some unstructured fields, but by default all
unknown fields are unstructured as well.  Things like attributes and
comments have no meaning for unstructured fields, but encoding does.

=chapter METHODS

=c_method new DATA

=default attributes    <not accepted>
=default extra         <not accepted>
=default is_structured <false>

When the DATA is specified as single line, the content part is considered to
be correcly (character) encoded and escaped.  Typically, it is a line as
read from file.  The folding of the line is kept as is.

In case more than one argument is provided, the second is considered the BODY.
Attributes and other special things are not defined for unstructured fields,
and therefore not valid options.  The BODY can be a single string, a single
OBJECT, or an array of OBJECTS.  The objects are stringified (into a comma
separated list).  Each BODY element is interpreted with the specified encoding.

When the BODY is empty, the construction of the object fails: C<undef> is
returned.

=examples

 my $s = Mail::Message::Field::Unstructured->new('Comment: Hi!');
 my $s = Mail::Message::Field::Unstructured->new('Comment', 'Hi!');

 # Use autodetect
 my $s = Mail::Message::Field::Full->new('Comment', 'Hi!');
 my $s = Mail::Message::Field::Full->new('Comment: Hi!');

=cut

my %implementation;

sub init($)
{   my ($self, $args) = @_;

    my $name = $args->{name};

    if(my $body = $args->{body})
    {   my @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
        $args->{body} = $self->encode(join(", ", @body), %$args);
    }
    else
    {   ($name, my $body) = split /\s*\:/, $name, 2;
        $args->{name} = $name;
        return () unless defined $body;
        $args->{body} = $body;
    }

    $self->SUPER::init($args) or return;
    $self;
}

#------------------------------------------

=section Access to the content

=method addAttribute ...

Attributes are not supported for unstructured fields.

=method addComment ...

Comments are not supported for unstructured fields.

=method addExtra ...

Extras are not supported for unstructured fields.

=cut

1;
