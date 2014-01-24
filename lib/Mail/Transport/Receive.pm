use strict;
use warnings;

package Mail::Transport::Receive;
use base 'Mail::Transport';

=chapter NAME

Mail::Transport::Receive - receive messages

=chapter SYNOPSIS

 my $receiver = Mail::Transport::POP3->new(...);
 my $message = $receiver->receive($id);

=chapter DESCRIPTION

Each object which extends M<Mail::Transport::Receive> implement
a protocol which can get messages into your application.  The internals
of each implementation can differ quite a lot, so have a look at each
separate manual page as well.

Current message receivers:

=over 4

=item * M<Mail::Transport::POP3>

Implements the POP3 protocol.  See also M<Mail::Box::POP3>.

=back

=chapter METHODS

=section Receiving mail

=method receive [$unique_message_id]
Receive one message from the remote server.  Some receivers will provide
the next message automatically, other are random access and use the
specified ID.

=cut

sub receive(@) {shift->notImplemented}

#------------------------------------------

=section Server connection

=section Error handling

=cut

1;
