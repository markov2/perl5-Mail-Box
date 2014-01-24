use strict;
use warnings;

package Mail::Transport::SMTP;
use base 'Mail::Transport::Send';

use Net::SMTP;

=chapter NAME

Mail::Transport::SMTP - transmit messages without external program

=chapter SYNOPSIS

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

 $message->send(via => 'smtp');

=chapter DESCRIPTION

This module implements transport of C<Mail::Message> objects by negotiating
to the destination host directly by using the SMTP protocol, without help of
C<sendmail>, C<mail>, or other programs on the local host.

=chapter METHODS

=c_method new %options

=default hostname <from Net::Config>
=default proxy    <from Net::Config>
=default via      C<'smtp'>
=default port     C<25>

=option  smtp_debug BOOLEAN
=default smtp_debug <false>

Simulate transmission: the SMTP protocol output will be sent to your
screen.

=option  helo HOST
=default helo <from Net::Config>

The fully qualified name of the sender's host (your system) which
is used for the greeting message to the receiver.  If not specified,
M<Net::Config> or else M<Net::Domain> are questioned to find it.
When even these do not supply a valid name, the name of the domain in the
C<From> line of the message is assumed.

=option  timeout SECONDS
=default timeout 120

The number of seconds to wait for a valid response from the server before
failing.

=option  username STRING
=default username undef

Use SASL authentication to contact the remote SMTP server (RFC2554).
This username in combination with new(password) is passed as arguments
to M<Net::SMTP> method auth.  Other forms of authentication are not
supported by Net::SMTP.  The C<username> can also be specified as an
M<Authen::SASL> object.

=option  password STRING
=default password undef

The password to be used with the new(username) to log in to the remote
server.

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

    $args->{via}  ||= 'smtp';
    $args->{port} ||= '25';

    $self->SUPER::init($args) or return;

    my $helo = $args->{helo}
      || eval { require Net::Config; $Net::Config::inet_domain }
      || eval { require Net::Domain; Net::Domain::hostfqdn() };

    $self->{MTS_net_smtp_opts}
       = { Hello   => $helo
         , Debug   => ($args->{smtp_debug} || 0)
         };

    $self;
}

#------------------------------------------

=method trySend $message, %options

Try to send the $message once.   This may fail, in which case this
method will return C<false>.  In list context, the reason for failure
can be caught: in list context C<trySend> will return a list of
five values:

 (success, error code, error text, error location, quit success)

Success and quit success are booleans.  The error code and -text are
protocol specific codes and texts.  The location tells where the
problem occurred.

=option  to ADDRESS|[ADDRESSES]
=default to []

Alternative destinations.  If not specified, the C<To>, C<Cc> and C<Bcc>
fields of the header are used.  An address is a string or a Mail::Address
object.

=option  from ADDRESS
=default from E<lt> E<gt>

Your own identification.  This may be fake.  If not specified, it is
taken from M<Mail::Message::sender()>, which means the content of the
C<Sender> field of the message or the first address of the C<From>
field.  This defaults to "E<lt> E<gt>", which represents "no address".

=notice No addresses found to send the message to, no connection made

=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    # From whom is this message.
    my $from = $args{from} || $message->sender || '<>';
    $from = $from->address if ref $from && $from->isa('Mail::Address');

    # Who are the destinations.
    if(defined $args{To})
    {   $self->log(WARNING =>
   "Use option `to' to overrule the destination: `To' would refer to a field");
    }

    my @to = map {$_->address} $self->destinations($message, $args{to});

    unless(@to)
    {   $self->log(NOTICE =>
            'No addresses found to send the message to, no connection made');
        return 1;
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
# next if $args{ignore_erroneous_destinations}
              return (0, $server->code, $server->message,"To $_",$server->quit);
        }

        $server->data;
        $server->datasend($_) foreach @header;
        my $bodydata = $message->body->file;

        if(ref $bodydata eq 'GLOB') { $server->datasend($_) while <$bodydata> }
        else    { while(my $l = $bodydata->getline) { $server->datasend($l) } }

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
    {
          next if $server->to($_);
# must we be able to disable this?
# next if $args{ignore_erroneous_destinations}
          $server->quit;
          return 0;
    }

    $server->data;
    $server->datasend($_) foreach @header;
    my $bodydata = $message->body->file;

    if(ref $bodydata eq 'GLOB') { $server->datasend($_) while <$bodydata> }
    else    { while(my $l = $bodydata->getline) { $server->datasend($l) } }

    $server->quit, return 0
        unless $server->dataend;

    $server->quit;
}

#------------------------------------------

=section Server connection

=method contactAnyServer

Creates the connection to the SMTP server.  When more than one hostname
was specified, the first which accepts a connection is taken.  An
M<IO::Socket::INET> object is returned.

=cut

sub contactAnyServer()
{   my $self = shift;

    my ($enterval, $count, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    my @hosts = ref $host ? @$host : $host;

    foreach my $host (@hosts)
    {   my $server = $self->tryConnectTo
         ( $host, Port => $port,
         , %{$self->{MTS_net_smtp_opts}}, Timeout => $timeout
         );

        defined $server or next;

        $self->log(PROGRESS => "Opened SMTP connection to $host.");

        if(defined $username)
        {   if($server->auth($username, $password))
            {    $self->log(PROGRESS => "$host: Authentication succeeded.");
            }
            else
            {    $self->log(ERROR => "Authentication failed.");
                 return undef;
            }
        }

        return $server;
    }

    undef;
}

#------------------------------------------

=method tryConnectTo $host, %options

Try to establish a connection to deliver SMTP to the specified $host.  The
%options are passed to the C<new> method of M<Net::SMTP>.

=cut

sub tryConnectTo($@)
{   my ($self, $host) = (shift, shift);
    Net::SMTP->new($host, @_);
}

#------------------------------------------

1;
