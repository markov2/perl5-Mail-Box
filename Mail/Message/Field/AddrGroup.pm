use strict;
use warnings;

package Mail::Message::Field::AddrGroup;
use base 'Mail::Reporter';

=head1 NAME

Mail::Message::Field::AddrGroup - A group of Mail::Message::Field::Address objects

=head1 SYNOPSIS

 my $g = Mail::Message::Field::AddrGroup->new('name');

 my $a = Mail::Message::Field::Address->new(...);
 $g->addAddress($a);
 
 my $f = Mail::Message::Field::Addresses->new;
 $f->addGroup($g);

=head1 DESCRIPTION

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new DATA

=examples

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return;

    $self->{MMFA_name} = defined $args->{name} ? $args->{name} : '';
    $self->{MMFA_addresses} = [];
    $self;
}

#------------------------------------------

=method name

Returns the name of this group.

=cut

sub name() { shift->{MMFA_name} }

#------------------------------------------

=method addAddress ADDRESS|OPTIONS

=cut

sub addAddress(@)
{   my $self  = shift;
    my $email = @_ && ref $_[0] ? shift
              : Mail::Message::Field::Address->new(@_);
    push @{$self->{MMFA_addresses}}, $email;
    $email;
}

#------------------------------------------

=method addresses

Returns all addresses defined in this group.

=cut

sub addresses() { @{shift->{MMFA_addresses}} }

#------------------------------------------

=method string

Returns the group as string.

=cut

sub string()
{   my $self = shift;
    my $name = $self->name;
    $name .= ': ' if length $name;
    $name . join(', ', $self->addresses) . ';';
}

#------------------------------------------

1;