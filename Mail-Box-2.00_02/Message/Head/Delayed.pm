
use strict;

package Mail::Message::Head::Delayed;
use base 'Mail::Reporter';

our $VERSION = '2.00_02';

# The relation to a Mail::Message::Head as full extention is faked: for
# each call on this object, we trigger to load the real ::Head.
use 'Mail::Message::Head';


=head1 NAME

Mail::Message::Head::Delayed - A not-read header of a Mail::Message

=head1 SYNOPSIS

    my Mail::Message::Head::Delayed $delayed = ...;
    $delayed->isa('Mail::Message::Head')  # true
    $delayed->guessBodySize               # undef
    $delayed->isDelayed                   # true

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box::Manager> first.

A C<Mail::Message::Head::Delayed> is used as place-holder, to be replaced
by a C<Mail::Message::Head> when someone accesses the header of a message.

=head2 METHODS

=over 4

=item new

(Class method)

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{MMHD_message} = $args->{message}
       or confess __PACKAGE__ . " requires a message.";

    $self;
}

#-------------------------------------------

sub isDelayed() { 1 }

#-------------------------------------------

sub message(;$) { $self->{MMHD_message} }

#-------------------------------------------

sub AUTOLOAD() {}

#-------------------------------------------

sub load() {}

#-------------------------------------------

sub guessBodySize() {undef}

sub guessTimestamp() {undef}

#------------------------------------------

=head1 AUTHOR

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 2.00_02, and far from complete.  Please
=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).

All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_02

=cut

1;
