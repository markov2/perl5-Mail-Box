use strict;
use warnings;

package Mail::Message::Field::Flex;
use base 'Mail::Message::Field';

use Carp;

=head1 NAME

Mail::Message::Field::Flex - one line of a message header

=head1 SYNOPSIS

=head1 DESCRIPTION

This is the flexible implementation of
a field: it can easily be extended because it stores its data in a hash
and the constructor (C<new>) and initializer (C<init>) are split.  However,
you pay the price in performance.
Mail::Message::Field::Fast is faster (as the name predicts).

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new DATA

If you stick to this flexible class of header fields, you have a bit
more facilities than with Mail::Message::Field::Fast.  Amongst it, you
can specify options with the creation.  Possible arguments:

=over 4

=item * B<new> LINE

=item * B<new> NAME, (BODY|OBJECTS), [ATTRIBUTES], [OPTIONS]

=back

To be able to distinguish the different parameters, you will have
to specify the OPTIONS as ARRAY of option pairs, or HASH of options.
The ATTRIBUTES are a flat list of key-value pairs.  The body is
specified as one BODY string, one OBJECT, or a reference to an array
of OBJECTS.  See Mail::Message::Field:

=option  attributes ATTRS
=default attributes []

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

    @$self{ qw/MMF_name MMF_body/ } = @$args{ qw/name body/ };

    $self->comment($args->{comment})
        if exists $args->{comment};

    my $attr = $args->{attributes};
    $self->attribute(shift @$attr, shift @$attr)
        while @$attr;

    $self;
}

#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

sub clone()
{   my $self = shift;
    (ref $self)->new($self->Name, $self->body);
}

#------------------------------------------

sub length()
{   my $self = shift;
    length($self->{MMF_name}) + 1 + length($self->{MMF_body});
}

#------------------------------------------

=head2 Access to the Field

=cut

#------------------------------------------

sub name() { lc shift->{MMF_name}}

#------------------------------------------

sub Name() { shift->{MMF_name}}

#------------------------------------------

sub folded(;$)
{   my $self = shift;
    return $self->{MMF_name}.':'.$self->{MMF_body}
        unless wantarray;

    my @lines = $self->folded_body;
    my $first = $self->{MMF_name}. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfolded_body($;@)
{   my $self = shift;
    $self->{MMF_body} = $self->fold($self->{MMF_name}, @_)
       if @_;

    $self->unfold($self->{MMF_body});
}

#------------------------------------------

sub folded_body($)
{   my ($self, $body) = @_;
    if(@_==2) { $self->{MMF_body} = $body }
    else      { $body = $self->{MMF_body} }

    wantarray ? split(m!(?<=\n)!, $body) : $body;
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

1;
