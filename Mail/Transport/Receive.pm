use strict;
use warnings;

package Mail::Transport::Receive;
use base 'Mail::Transport';

=head1 NAME

Mail::Transport::Receive - receive messages

=head1 SYNOPSIS

 my $receiver = Mail::Transport::POP3->new(...);
 my $message = $receiver->receive($id);

=head1 DESCRIPTION

Each object which extends L<Mail::Transport::Receive> implement
a protocol which can get messages into your application.  The internals
of each implementation can differ quite a lot, so have a look at each
separate manual page as well.

Current message receivers:

=over 4

=item * Mail::Transport::POP3

Implements the POP3 protocol.  See also Mail::Box::POP3.

=back

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

=cut

#------------------------------------------

=head2 Receiving Mail

=cut

#------------------------------------------

=method receive [UNIQUE-MESSAGE-ID]

Receive one message from the remote server.  Some receivers will provide
the next message automatically, other are random access and use the
specified ID.

=cut

sub receive(@) {shift->notImplemented}

#------------------------------------------

1;
