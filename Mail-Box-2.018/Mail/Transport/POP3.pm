use strict;
use warnings;

package Mail::Transport::POP3;
use base 'Mail::Transport::Receive';

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::POP3 - receive messages via POP3

=head1 CLASS HIERARCHY

 Mail::Transport::POP3
 is a Mail::Transport::Receive
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $receiver = Mail::Transport::POP3->new(...);
 my $message = $receiver->receive($id);

=head1 DESCRIPTION

Receive messages via the POP3 protocol.  This object handles the contact
with one POP3 server, and recovers broken connections automatically.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT), L<Mail::Transport::Receive> (MTR).

The general methods for C<Mail::Transport::POP3> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]               top UIDL, [MAXLINES]
      new OPTIONS                       MR trace [LEVEL]
  MTR receive [UNIQUE-MESSAGE-ID]          url
   MR report [LEVEL]                    MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
      contactServer                     MR notImplemented
   MT findBinary NAME [, DIRECTOR...    MT remoteHost
   MR inGlobalDestruction               MT retry

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION        DESCRIBED IN             DEFAULT
 authenticate  Mail::Transport::POP3    'LOGIN'
 head_type     Mail::Transport::Receive 'Mail::Message::Head::Complete'
 head_opts     Mail::Transport::Receive {}
 hostname      Mail::Transport          'localhost'
 interval      Mail::Transport          30
 message_type  Mail::Transport::Receive 'Mail::Message'
 message_opts  Mail::Transport::Receive undef
 log           Mail::Reporter           'WARNINGS'
 password      Mail::Transport          undef
 proxy         Mail::Transport          undef
 retry         Mail::Transport          undef
 timeout       Mail::Transport          120
 trace         Mail::Reporter           'WARNINGS'
 username      Mail::Transport          undef
 via           Mail::Transport          'pop3'

=over 4

=item * authenticate =E<gt> 'LOGIN'|'APOP'

Use the old LOGIN authentication (unencryped, default) or the newer APOP.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{via} = 'pop3';
    $self->SUPER::init($args);

    $self->{MTP_auth} = $self->{authenticate} || 'LOGIN';
    $self;
}

#------------------------------------------

=item url

Represent this pop3 connection as URL.

=cut

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

#------------------------------------------

=item top UIDL, [MAXLINES]

Returns a reference to an array which contains the header of the message
with the specified UIDL.  The optional integer MAXLINES specifies the
number of lines from the body which are wanted: by default all.

=cut

sub top($;$)
{   my ($self, $uidl, $ask) = (shift, shift);
    undef;
}

#------------------------------------------

=back

=head1 METHODS for extensions writers

=over 4

=cut

#------------------------------------------

=item contactServer

=cut

sub contactServer()
{   my $self = shift;

    my ($interval, $retries, $timeout)   = $self->retry;
    my ($hostname, $port, $username, $password) = $self->remoteHost;
}

#------------------------------------------

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
