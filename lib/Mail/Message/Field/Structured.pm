use strict;
use warnings;

package Mail::Message::Field::Structured;
use base 'Mail::Message::Field::Full';

use Mail::Message::Field::Attribute;

=chapter NAME

Mail::Message::Field::Structured - one line of a structured message header

=chapter SYNOPSIS

 my $f = Mail::Message::Field::Full
            ->new('Content-Type' => 'text/html');
 # $f is now a Mail::Message::Field::Structured
 # NOT READY YET!!!

 my @encode = (charset => 'jp', use_continuations => 1);
 $f->attribute('filename=passwd');
 $f->attribute(filename => 'passwd', @encode);

 my $attr = Mail::Message::Field::Attribute->new(...);
 $f->attribute($attr);

=chapter DESCRIPTION

=chapter METHODS

=c_method new DATA

=over 4

=item * B<new> LINE

Pass a LINE as it could be found in a file: a (possibly folded) line
which is terminated by a new-line.

=item * B<new> NAME, BODY, OPTIONS

A set of values which shape the line.

=back

The NAME is a wellformed header name (you may use wellformedName()) to
be sure about the casing.  The BODY is a string, one object, or an
ref-array of objects.  In case of objects, they must fit to the
constructor of the field: the types which are accepted may differ.
The optional ATTRIBUTE list contains M<Mail::Message::Field::Attribute>
objects.  Finally, there are some OPTIONS.

=option  attributes ATTRS
=default attributes C<[]>

There are various ways to specify these attributes: pass a reference
to an array which list of key-value pairs representing attributes,
or reference to a hash containing these pairs, or an array with
M<Mail::Message::Field::Attribute> objects.

=option  extra STRING
=default extra undef

Text which is appended after the line (preceded by a semicolon).

=example of a structured field
 my @attrs   = (Mail::Message::Field::Attribute->new(...), ...);
 my @options = (extra => 'the color blue');
 my $t = Mail::Message::Field::Full->new(To => \@addrs, @attrs, @options);

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->addExtra($args->{extra})
        if exists $args->{extra};

    my $attr = $args->{attributes} || [];
    $attr    = [ %$attr ] if ref $attr eq 'HASH';

    while(@$attr)
    {   my $name = shift @$attr;
        if(ref $name) { $self->attribute($name) }
        else          { $self->attribute($name, shift @$attr) }
    }

    $self->{MMFS_attrs} = {};
    $self->{MMFS_extra} = ();
    $self;
}

#------------------------------------------

sub clone() { dclone(shift) }

#------------------------------------------

=section Access to the content

=method attribute OBJECT|(STRING, OPTIONS)|(NAME,VALUE,OPTIONS)

Add an attribute to the field.  The attributes are added left-to-right into
the string representation of the field, although the order of the attributes
is un-important, according to the RFCs.

You may pass a fully prepared M<Mail::Message::Field::Attribute> OBJECT,
if you like to do all preparations for correct representation of the
data yourself.  You may also pass one STRING, which is a fully prepared
attribute.  This STRING will not be changed, so be careful about quoting
and encodings.

As third possibility, you can specify an attribute NAME and its VALUE.
An attribute object will be created for you implicitly in both
cases where such object is not supplied, passing the OPTIONS.  See
M<Mail::Message::Field::Attribute::new()> about the available OPTIONS.

The attribute object is returned, however, when continuations are used this
may be an object you already know about.  C<undef> is returned when
construction fails (when the attribute is incorrect).

=examples

 $f->attribute(filename => 'passwd');
 $f->attribute(filename => 'passwd', use_continuations => 0);

 my $attr = Mail::Message::Field::Attribute->new(...);
 $f->attribute($attr);

=cut

sub attribute($;$)
{   my ($self, $attr) = (shift, shift);
    my $name;
    if(ref $attr) { $name = $attr->name }
    elsif( !@_ )  { return $self->{MMFS_attrs}{lc $attr} }
    else
    {   $name = $attr;
        $attr = Mail::Message::Field::Attribute->new($name, @_);
    }

    delete $self->{MMFF_body};
    if(my $old =  $self->{MMFS_attrs}{$name})
    {   $old->mergeComponent($attr);
        return $old;
    }
    else
    {   $self->{MMFS_attrs}{$name} = $attr;
        return $attr;
    }
}

#------------------------------------------

=method attributes

Returns a list with all attributes, which are all
M<Mail::Message::Field::Attribute> objects.  The attributes are not
ordered in any way.  The list may be empty.  Double attributes or
continuations are folded into one.

=cut

sub attributes() { values %{shift->{MMFS_attrs}} }

#------------------------------------------

sub beautify() { delete shift->{MMFF_body} }

#------------------------------------------

1;
