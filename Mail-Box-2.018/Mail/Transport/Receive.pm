use strict;
use warnings;

package Mail::Transport::Receive;
use base 'Mail::Transport';

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::Receive - receive messages

=head1 CLASS HIERARCHY

 Mail::Transport::Receive
 is a Mail::Transport
 is a Mail::Reporter

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

=item * C<Mail::Transport::POP3>

Implements the POP3 protocol.  See also C<Mail::Box::POP3>.

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT).

The general methods for C<Mail::Transport::Receive> objects:

   MR errors                            MR report [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR reportAll [LEVEL]
      new OPTIONS                       MR trace [LEVEL]
      receive [UNIQUE-MESSAGE-ID]       MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
   MT findBinary NAME [, DIRECTOR...    MT remoteHost
   MR inGlobalDestruction               MT retry
   MR logPriority LEVEL

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION        DESCRIBED IN             DEFAULT
 hostname      Mail::Transport          'localhost'
 interval      Mail::Transport          30
 log           Mail::Reporter           'WARNINGS'
 password      Mail::Transport          undef
 proxy         Mail::Transport          undef
 retry         Mail::Transport          undef
 timeout       Mail::Transport          120
 trace         Mail::Reporter           'WARNINGS'
 username      Mail::Transport          undef
 via           Mail::Transport          undef

=cut

#sub init($)
#{   my ($self, $args) = @_;
#
#    $self->SUPER::init($args);
#
#    $self;
#}

#------------------------------------------

=item receive [UNIQUE-MESSAGE-ID]

Receive one message from the remote server.  Some receivers will provide
the next message automatically, other are random access and use the
specified ID.

=cut

sub receive(@) {shift->notImplemented}


=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
