use strict;
use warnings;

package Mail::Transport::SMTP;
use base 'Mail::Transport';

#use Mail::Transport::SMTP::Server;
use Net::SMTP;

our $VERSION = 2.016;

=head1 NAME

Mail::Transport::SMTP - transmit messages without external program

=head1 CLASS HIERARCHY

 Mail::Transport::SMTP
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

 $message->send(via => 'smtp');

=head1 DESCRIPTION

USE WITH CARE! THIS MODULE IS VERY NEW, SO MAY CONTAIN BUGS

This module implements transport of C<Mail::Message> objects by negotiating
to the destination host directly by using the SMTP protocol, without help of
C<sendmail>, C<mail>, or other programs on the local host.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT).

The general methods for C<Mail::Transport::SMTP> objects:

      contactAnyServer                  MT send MESSAGE, OPTIONS
   MR errors                            MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]               tryConnectTo HOST, OPTIONS
      new OPTIONS                       MT trySend MESSAGE, OPTIONS
   MR report [LEVEL]                    MR warnings
   MR reportAll [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MT findBinary NAME [, DIRECTOR...    MR notImplemented
   MR inGlobalDestruction               MT putContent MESSAGE, FILEHAN...

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION       DESCRIBED IN           DEFAULT
 debug        Mail::Transport::SMTP  0
 helo_domain  Mail::Transport::SMTP  <from Net::Config>
 log          Mail::Reporter         'WARNINGS'
 proxy        Mail::Transport::STMP  <from Net::Config>
 timeout      Mail::Transport::SMTP  120
 trace        Mail::Reporter         'WARNINGS'
 via          Mail::Transport        <unused>

=over 4

=item debug =E<gt> BOOLEAN

Simulate transmission: the SMTP protocol output will be sent to your
screen.

=item helo_domain =E<gt> HOST

The fully qualified name of the sender's host (your system) which
is used for the greeting message to the receiver.  If not specified,
L<Net::Config> or else L<Net::Domain> are questioned to find it.
When even these do not supply a valid name, the name of the domain in the
C<From> line of the message is assumed.

=item proxy =E<gt> HOST|ARRAY-OF-HOSTS

Specifies the system which is used as relay HOST.  By default, the
configuration of L<Net::Config> is used.  When more than one hostname
is specified, the first host which can be contacted will be used.

=item timeout =E<gt> SECONDS

The number of seconds to wait for a valid response from the server before
failing.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    # Collect the data for a connection to the server

    my $hosts   = $args->{proxy};
    unless($hosts)
    {   require Net::Config;
        $hosts  = $Net::Config::NetConfig{smtp_hosts};
        undef $hosts unless @$hosts;
    }

    my @hosts
      = ref $hosts     ? @$hosts
      : defined $hosts ? $hosts
      :                 'localhost';

    $self->{MTS_hosts} = \@hosts;

    my $helo = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self->{MTS_net_smtp_opts}
       = { Hello   => $helo
         , Timeout => (defined $args->{timeout} ? $args->{timeout} : 120)
         , Debug   => ($args->{debug} || 0)
         };

    $self;
}


#------------------------------------------

sub trySend($)
{   my ($self, $message) = @_;
    my $server = $self->contactAnyServer or return 0;

    my $from   = $message->from;
    $server->mail($message->from->address);
    $server->to($_->address) foreach $message->destinations;

    $server->data;

    # Print the message's header
    # This is first prepared in an array of lines.

    my @lines;
    require IO::Lines;
    my $lines = IO::Lines->new(\@lines);
    $message->head->printUndisclosed($lines);
    $server->datasend($_) foreach @lines;

    # Print the message's body
    my $bodydata = $message->body->file;
    $server->datasend($_) while <$bodydata>;

    my $success = $server->dataend;
    my $error   = $success ? 0 : $server->code;

    $server->quit;
    wantarray ? ($success, $error) : $success;
}

#------------------------------------------

=item contactAnyServer

Creates the connection to the SMTP server.  When more than one hostname
was specified, the first which accepts a connection is taken.  An
C<IO::Server::INET> object is returned.

=cut

sub contactAnyServer()
{   my $self = shift;

    foreach my $host (@{$self->{MTS_hosts}})
    {   my $server = $self->tryConnectTo($host, %{$self->{MTS_net_smtp_opts}} )
            or next;

        $self->log(PROGRESS => "Opened SMTP connection to $host.\n");
        return $server;
    }

    undef;
}

#------------------------------------------

=item tryConnectTo HOST, OPTIONS

Try to establish a connection to deliver SMTP to the specified HOST.  The
OPTIONS are passed to the C<new> method of L<Net::SMTP>.

=cut

sub tryConnectTo($@)
{   my ($self, $host) = (shift, shift);
    Net::SMTP->new($host, @_);
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

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
