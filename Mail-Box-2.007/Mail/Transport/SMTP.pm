use strict;
use warnings;

package Mail::Transport::SMTP;
use base 'Mail::Transport';

use Carp;
use IO::Socket::INET;
use Net::Cmd;

our $VERSION = 2.007;

=head1 NAME

Mail::Transport::SMTP - transmit messages without external program

=head1 CLASS HIERARCHY

 Mail::Transport::SMTP
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

=head1 DESCRIPTION

UNDER CONSTRUCTIONS.  CANNOT BE USED YET.  (Suggestions welcome)

This module implements transport of C<Mail::Message> objects by negotiating
to the destination host directly, without help of C<sendmail>, C<mail>, or
other programs on the local host.

=head1 METHOD INDEX

The general methods for C<Mail::Transport::SMTP> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]               send MESSAGE, OPTIONS
      new OPTIONS                       MR trace [LEVEL]
   MR report [LEVEL]                    MT trySend MESSAGE, OPTIONS

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
      contactServer                     MR logSettings
   MT findBinary NAME [, DIRECTOR...    MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
   MT = L<Mail::Transport>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION       DESCRIBED IN           DEFAULT
 helo_domain  Mail::Transport::SMTP  <from Net::Config>
 log          Mail::Reporter         'WARNINGS'
 port         Mail::Transport::SMTP  'smtp(25)'
 proxy        Mail::Transport::STMP  <from Net::Config>
 timeout      Mail::Transport::SMTP  120
 trace        Mail::Reporter         'WARNINGS'
 via          Mail::Transport        <unused>

=over 4

=item helo_domain =E<gt> HOST

The fully qualified name of the sender's host (your system) which
is used for the greeting message to the receiver.  If not specified,
L<Net::Config> or else L<Net::Domain> are questioned to find it.
When even those are nor working, the domain is taken from the
C<From> line of the message.

=item port =E<gt> STRING

The port to be used when contacting the server. L<IO::Socket>
describes this field as C<PeerPort>.

=item proxy =E<gt> HOST|ARRAY-OF-HOSTS

Specifies the system which is used as relay HOST.  By default, the
configuration of L<Net::Config> is used.  When more than one hostname
is specified, the first host which can be contacted will be used.

=item timeout =E<gt> SECONDS

The number of sections to wait maximally for contacting the server.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    # Collect the data for a connection to the server

    my $host    = $args->{proxy};
    unless($host)
    {   require Net::Config;
        $host   = $Net::Config::NetConfig{smtp_hosts};
    }

    confess "No server name specified, nor configured."
        unless $host;

    my @hosts   = ref $host ? @$host : $host;
    my $timeout = defined $args->{timeout} ? $args->{timeout} : 120;
    my $port    = $args->{port} || 'smtp(25)';

    $self->{MTS_hosts} = \@hosts;
    $self->{MTS_sock_opts}
       = [ PeerPort => $port, Proto => 'tcp', Timeout => $timeout ];

    $self->{MTS_helo_domain}
       = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self;
}


#------------------------------------------

sub trySend($)
{   my ($self, $message) = @_;
    my $server = $self->contactServer or return 0;

    my $from   = $message->from;
    my $domain = $self->{MTS_helo_domain};
    $domain    = $1 if !$domain && $from =~ m/\@(\S+)$/;

# Here, the filehandle has to start being intelligent.  Maybe a
# tie inbetween (like Net::STMP) which adds CRLF's to the end?
# But probably it is better to avoid the Net::* things totally.

    # HELO!

    my $ok     = $server->command(EHLO => $domain)->response;
    my ($welcome, @capable) = $server->message;
    my %caps;

    if($ok==CMD_OK)
    {   foreach (@capable)
        {   $caps{uc $1} = $2 if m/(\S+)\s+([^\n]*)/;
        }
    }
    elsif(($ok = $server->command(HELO => $domain)->response)==CMD_OK)
    {   ($welcome) = $server->message;
    }

    unless($ok==CMD_OK && defined $welcome)
    {   $server->close;
        return 0;
    }

    # Send from and to

    $server->command(MAIL => 'FROM:<'.$from->address.'>');

    $server->command(RCPT => 'TO:<'.$_->address.'>')
        foreach $message->destinations;

    # Send the message

    $server->command('DATA');

confess "Not fully implemented yet";

    $message->printUndislosed($server);
    $server->dataend;

    #

    $server->command('QUIT');
    $server->close;

    1;
}

#------------------------------------------

=item send MESSAGE, OPTIONS

Transmit the MESSAGE.  It returns true when the transmission was succesfully
completed.  Some extensions to C<Mail::Transport> may offer OPTIONS, but at
least the following are supported:

 OPTIONS      DESCRIBED IN              DEFAULT
 interval     Mail::Transport           30
 retry        Mail::Transport           undef

=cut

sub send($@)
{   my ($self, $message, %args) = @_;
    my @to    = $message->destinations;
    my $msgid = $message->messageId;

    my $retry = defined $args{retry} ? $args{retry} : -1;
    while($retry >= 0)
    {   my @failed;
        while(@to)
        {   my $to = shift @to;
            if($self->sendToOne($message, $to))
                 { $self->log(NOTICE => "Sent $msgid to ".$to->format.".\n") }
            else { push @failed, $to }
        }

        last unless @to;
        @to = @failed;
        $retry--;
        sleep( $args{interval} || 30);
    }

    $self->log(NOTICE => "Failed to transmit $msgid to ". $_->format. ".\n")
        foreach @to;

    @to==0;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item contactServer

Creates the connect to the SMTP server.  When more than one hostname
was specified, the first which accepts a connection is taken.  An
C<IO::Server::INET> object is returned.

=cut

sub contactServer()
{   my $self = shift;

    my $server;
    my @options = @{$self->{MTS_sock_opts}};

    foreach my $host (@{$self->{MTS_hosts}})
    {
        $server = IO::Server::INET->new(PeerAddr => $host, @options)
            or next;

        last if $server->response==CMD_OK;
        $server->close;
    }

    $server;
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.007.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
