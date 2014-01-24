use strict;
use warnings;

package Mail::Message::Field::Unstructured;
use base 'Mail::Message::Field::Full';

=chapter NAME

Mail::Message::Field::Unstructured - smart unstructured field

=chapter SYNOPSIS

 my $f = Mail::Message::Field::Unstructured->new(Comments => 'hi!');

=chapter DESCRIPTION

Unstructured fields do contain information which is not restricted in
any way.  RFC2822 defines some unstructured fields, but by default all
unknown fields are unstructured as well.  Things like attributes and
comments have no meaning for unstructured fields, but encoding does.

=chapter METHODS

=c_method new $data

When the $data is specified as single line, the content part is considered to
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

 my $s = Mail::Message::Field::Unstructured->new('Comment', 'Hi!');

 # Use autodetect
 my $s = Mail::Message::Field::Full->new('Comment', 'Hi!');
 my $s = Mail::Message::Field::Full->new('Comment: Hi!');

=cut

sub init($)
{   my ($self, $args) = @_;

    if($args->{body} && ($args->{encoding} || $args->{charset}))
    {   $args->{body} = $self->encode($args->{body}, %$args);
    }

    $self->SUPER::init($args) or return;

    $self->log(WARNING=>"Attributes are not supported for unstructured fields")
        if defined $args->{attributes};

    $self->log(WARNING => "No extras for unstructured fields")
        if defined $args->{extra};

    $self;
}

=section Access to the content
=cut

1;
