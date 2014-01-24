use strict;
use warnings;

package Mail::Message::Field::Flex;
use base 'Mail::Message::Field';

use Carp;

=chapter NAME

Mail::Message::Field::Flex - one line of a message header

=chapter SYNOPSIS

=chapter DESCRIPTION

This is the flexible implementation of a field: it can easily be
extended because it stores its data in a hash and the constructor
(C<new>) and initializer (C<init>) are split.  However, you pay the
price in performance.  M<Mail::Message::Field::Fast> is faster (as the
name predicts).

=chapter METHODS

=c_method new $data

If you stick to this flexible class of header fields, you have a bit
more facilities than with M<Mail::Message::Field::Fast>.  Amongst it, you
can specify options with the creation.  Possible arguments:

=over 4

=item * B<new> LINE

ass a LINE as it could be found in a file: a (possibly folded) line
which is terminated by a new-line.

=item * B<new> NAME, (BODY|OBJECTS), [ATTRIBUTES], OPTIONS

A set of values which shape the line.

=back

To be able to distinguish the different parameters, you will have
to specify the OPTIONS as ARRAY of option pairs, or HASH of options.
The ATTRIBUTES are a flat list of key-value pairs.  The body is
specified as one BODY string, one OBJECT, or a reference to an array
of OBJECTS.  See M<Mail::Message::Field>:

=option  attributes ATTRS
=default attributes C<[]>

Reference to array with list of key-value pairs representing attributes,
or reference to a hash containing these pairs.  This is an alternative
notation for specifying ATTRIBUTES directly as method arguments.

=option  comment STRING
=default comment undef

A pre-formatted list of attributes.

=cut

sub new($;$$@)
{   my $class  = shift;
    my $args   = @_ <= 2 || ! ref $_[-1] ? {}
                : ref $_[-1] eq 'ARRAY'  ? { @{pop @_} }
                :                          pop @_;

    my ($name, $body) = $class->consume(@_==1 ? (shift) : (shift, shift));
    return () unless defined $body;

    # Attributes preferably stored in array to protect order.
    my $attr   = $args->{attributes};
    $attr      = [ %$attr ] if defined $attr && ref $attr eq 'HASH';
    push @$attr, @_;

    $class->SUPER::new(%$args, name => $name, body => $body,
         attributes => $attr);
}

sub init($)
{   my ($self, $args) = @_;

    @$self{ qw/MMFF_name MMFF_body/ } = @$args{ qw/name body/ };

    $self->comment($args->{comment})
        if exists $args->{comment};

    my $attr = $args->{attributes};
    $self->attribute(shift @$attr, shift @$attr)
        while @$attr;

    $self;
}

#------------------------------------------

sub clone()
{   my $self = shift;
    (ref $self)->new($self->Name, $self->body);
}

#------------------------------------------

sub length()
{   my $self = shift;
    length($self->{MMFF_name}) + 1 + length($self->{MMFF_body});
}

#------------------------------------------

sub name() { lc shift->{MMFF_name}}

#------------------------------------------

sub Name() { shift->{MMFF_name}}

#------------------------------------------

sub folded(;$)
{   my $self = shift;
    return $self->{MMFF_name}.':'.$self->{MMFF_body}
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->{MMFF_name}. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfoldedBody($;@)
{   my $self = shift;
    $self->{MMFF_body} = $self->fold($self->{MMFF_name}, @_)
       if @_;

    $self->unfold($self->{MMFF_body});
}

#------------------------------------------

sub foldedBody($)
{   my ($self, $body) = @_;
    if(@_==2) { $self->{MMFF_body} = $body }
    else      { $body = $self->{MMFF_body} }

    wantarray ? (split /^/, $body) : $body;
}

#------------------------------------------

1;
