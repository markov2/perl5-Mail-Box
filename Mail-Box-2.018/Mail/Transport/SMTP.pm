use strict;
use warnings;

package Mail::Transport::SMTP;
use base 'Mail::Transport::Send';

use Net::SMTP;

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::SMTP - transmit messages without external program

=head1 CLASS HIERARCHY

 Mail::Transport::SMTP
 is a Mail::Transport::Send
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

 $message->send(via => 'smtp');

=head1 DESCRIPTION

This module implements transport of C<Mail::Message> objects by negotiating
to the destination host directly by using the SMTP protocol, without help of
C<sendmail>, C<mail>, or other programs on the local host.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT), L<Mail::Transport::Send> (MTS).

The general methods for C<Mail::Transport::SMTP> objects:

      contactAnyServer                 MTS send MESSAGE, OPTIONS
   MR errors                            MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]               tryConnectTo HOST, OPTIONS
      new OPTIONS                          trySend MESSAGE, OPTIONS
   MR report [LEVEL]                    MR warnings
   MR reportAll [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
   MT findBinary NAME [, DIRECTOR...   MTS putContent MESSAGE, FILEHAN...
   MR inGlobalDestruction               MT remoteHost
   MR logPriority LEVEL                 MT retry

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION      DESCRIBED IN           DEFAULT
 debug       Mail::Transport::SMTP  0
 helo_domain Mail::Transport::SMTP  <from Net::Config>
 hostname    Mail::Transport        <from Net::Config>
 interval    Mail::Transport        30
 log         Mail::Reporter         'WARNINGS'
 password    Mail::Transport        <not used>
 proxy       Mail::Transport::STMP  <from Net::Config>
 retry       Mail::Transport        undef
 timeout     Mail::Transport::SMTP  120
 trace       Mail::Reporter         'WARNINGS'
 username    Mail::Transport        <not used>
 via         Mail::Transport        'smtp'


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

=item timeout =E<gt> SECONDS

The number of seconds to wait for a valid response from the server before
failing.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    my $hosts   = $args->{hostname};
    unless($hosts)
    {   require Net::Config;
        $hosts  = $Net::Config::NetConfig{smtp_hosts};
        undef $hosts unless @$hosts;
        $args->{hostname} = $hosts;
    }

    $args->{via} = 'smtp';

    $self->SUPER::init($args);

    my $helo = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self->{MTS_net_smtp_opts}
       = { Hello   => $helo
         , Debug   => ($args->{debug} || 0)
         };

    $self;
}


#------------------------------------------

=item trySend MESSAGE, OPTIONS

Try to send the MESSAGE once.   This may fail, in which case this
method will return C<false>.  In list context, the reason for failure
can be caught: in list context C<trySend> will return a list of
five values:

 (success, error code, error text, error location, quit success)

Success and quit success are booleans.  The error code and -text are
protocol specific codes and texts.  The location tells where the
problem occurred.

As OPTIONS, you can use

=over 4

=item * to => ADDRESS|[ADDRESSES]

Alternative destinations.  If not specified, the C<To>, C<Cc> and C<Bcc>
fields of the header are used.  An address is a string or a L<Mail::Address>
object.

=item * from => ADDRESS

Your own identification.  This may be fake.  If not specified, it is
taken from the C<From> field in the header.

=back

=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    # From whom is this message.
    my $from = $args{from} || $message->from;
    $from = $from->address if ref $from;

    # Who are the destinations.
    my $to   = $args{to}   || [$message->destinations];
    my @to   = ref $to eq 'ARRAY' ? @$to : ($to);
    foreach (@to)
    {   $_ = $_->address if ref $_ && $_->isa('Mail::Address');
    }

    # Prepare the header
    my @header;
    require IO::Lines;
    my $lines = IO::Lines->new(\@header);
    $message->head->printUndisclosed($lines);

    #
    # Send
    #

    if(wantarray)
    {   # In LIST context
        my $server;
        return (0, 500, "Connection Failed", "CONNECT", 0)
            unless $server = $self->contactAnyServer;

        return (0, $server->code, $server->message, 'FROM', $server->quit)
            unless $server->mail($from);

        foreach (@to)
        {     next if $server->to($_);
# must we be able to disable this?
# next if $args{ignore_erroneous_desinations}
              return (0, $server->code, $server->message,"To $_",$server->quit);
        }

        $server->data;
        $server->datasend($_) foreach @header;
        my $bodydata = $message->body->file;
        $server->datasend($_) while <$bodydata>;

        return (0, $server->code, $server->message, 'DATA', $server->quit)
            unless $server->dataend;

        return ($server->quit, $server->code, $server->message, 'QUIT',
                $server->code);
    }

    # in SCALAR context
    my $server;
    return 0 unless $server = $self->contactAnyServer;

    $server->quit, return 0
        unless $server->mail($from);

    foreach (@to)
    {     next if $server->to($_);
# must we be able to disable this?
# next if $args{ignore_erroneous_desinations}
          $server->quit;
          return 0;
    }

    $server->data;
    $server->datasend($_) foreach @header;
    my $bodydata = $message->body->file;
    $server->datasend($_) while <$bodydata>;

    $server->quit, return 0
        unless $server->dataend;

    $server->quit;
}

#------------------------------------------

=item contactAnyServer

Creates the connection to the SMTP server.  When more than one hostname
was specified, the first which accepts a connection is taken.  An
C<IO::Server::INET> object is returned.

=cut

sub contactAnyServer()
{   my $self = shift;

    my ($interval, $count, $timeout) = $self->retry;
    my ($host, $username, $password) = $self->remoteHost;
    my @hosts = ref $host ? @$host : $host;

    foreach my $host (@hosts)
    {   my $server = $self->tryConnectTo
         ( $host
         , %{$self->{MTS_net_smtp_opts}}, Timeout => $timeout
         );

        defined $server or next;

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

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
