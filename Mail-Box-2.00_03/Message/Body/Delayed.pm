use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Object::Realize::Later
    becomes => 'Mail::Message::Body',
    realize => sub {shift->message->loadBody};

our $VERSION = '2.00_03';


use Carp;

=head1 NAME

Mail::Message::Body::Delayed - Body of a Mail::Message but not read yet.

=head1 SYNOPSIS

   See Mail::Message::Body

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST.  Message bodies of this type will be
replaced by another type the moment you access the content.  In this
documentation you will find the description of how a message body gets
delay loaded.

=head1 METHODS

The body will currently only stay delayed when you call
for C<isDelayed>, C<message>, C<guessSize>, and maybe for C<isMultipart>.

=over 4

=item new OPTIONS

The constuctor used the following options:

 OPTION            DESCRIBED IN          DEFAULT
 log               Mail::Reporter        'WARNINGS'
 message           Mail::Message::Body   <obligatory>
 size              Mail::Message::Body   undef
 trace             Mail::Reporter        'WARNINGS'

=cut

sub init($)
{   my ($self, $args) = @_;
    croak "Message require to create a delayed body.\n"
        unless $self->{MMBD_message} = $args->{message};

    $self->{MMBD_size} = $args->{size};
    $self;
}

sub isDelayed()   {1}
sub isMultipart() {shift->message->head->isMultipart}
sub message()     {shift->{MMBD_message}}
sub guessSize()   {shift->{MMBD_size}}

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 1.318, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Message>
L<Mail::Message::Body>
L<Mail::Box::Manager>

=cut

1;
