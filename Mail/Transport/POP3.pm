use strict;
use warnings;

package Mail::Transport::POP3;
use base 'Mail::Transport::Receive';

=head1 NAME

Mail::Transport::POP3 - receive messages via POP3

=head1 SYNOPSIS

 my $receiver = Mail::Transport::POP3->new(...);
 my $message = $receiver->receive($id);

=head1 DESCRIPTION

Receive messages via the POP3 protocol.  This object handles the contact
with one POP3 server, and recovers broken connections automatically.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=option  authenticate 'LOGIN'|'APOP'
=default authenticate 'LOGIN'

Use the old LOGIN authentication (unencrypted, default) or the newer APOP.

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{via} = 'pop3';
    $self->SUPER::init($args);

    $self->{MTP_auth} = $self->{authenticate} || 'LOGIN';
    $self;
}

#------------------------------------------

=head2 Receiving Mail

=cut

#------------------------------------------

=method messages

Returns a list of all uidl's which are known by the server on this moment.

=cut

sub messages()
{   my $self = shift;
    
    my $server = $self->contactServer;

    $self->{MTP_msgs} = { reverse $server->send('UIDL') }
        unless exists $self->{MTP_msgs};

    keys %{$self->{MTP_msgs}};
}

#------------------------------------------

=method uidl2seqnr UIDL

Translates the unique UIDL of a message into a sequence number which
represents the message as long a this connection to the POP3 server
exists.  When the message has been deleted for some reason, C<undef>
is returned.

=cut

sub uidl2seqnr($)
{   my ($self, $uidl) = @_;

    exists $self->{MTP_msgs} || $self->message || return;
    $self->{MTP_msgs}{$uidl};
}

#------------------------------------------

=method header UIDL, [BODYLINES]

Returns a reference to an array which contains the header of the message
with the specified UIDL.  The optional integer BODYLINES specifies the
number of lines from the body which are wanted: by default all.

=example

 my $ref_lines = $pop3->header($uidl);
 print @$ref_lines;

=cut

sub header($;$)
{   my ($self, $uidl, $bodylines) = (shift, shift || 0);

    my $server = $self->contactServer
       or return [];

    my $seqnr  = $self->uidl2seqnr($uidl);
    return [] unless defined $seqnr;

    my @header = $server->send(TOP => $seqnr, $bodylines);
    \@header;
}

#------------------------------------------

=method size UIDL

Returns the size of the message which is indicated by the UIDL, in octets.
If the message is remotely deleted, this will return C<undef>.

=cut

# When the size() is called for the first time, POP3 method list() should
# be called and all sizes collected.  Those values should be cached for
# performance reasons.

sub size($)
{   my ($self, $uidl) = @_;

    return $self->{MTP_sizes}{$uidl}
        if exists $self->{MTP_sizes};

    $self->messages or return;  # be sure we have messages
    my %uidl_of = reverse %{$self->{MTP_msgs}};

    my $server  = $self->contactServer or return;
    my $sizes   = $self->{MTP_sizes} = {};

    my @sizes = $server->send('UIDL');
    foreach (@sizes)
    {   my ($seqnr, $size) = @_;
        my $id = $uidl_of{$seqnr};
        $sizes->{$id} = $size if defined $id;
    }

    return $self->{MTP_sizes}{$uidl};
}

#------------------------------------------

=method stat

Returns the I<maildrop> of the pop server; a list of two elements: the
number of messages followed by the total folder size in octets.

=example

 my ($nr_messages, $total_size) = $pop3->stat;

=cut

sub stat()
{   my $self = shift;

    my $server = $self->contactServer
        or return (0,0);

    my ($nr, $size) = split " ", $server->send('STAT');
    ($nr, $size);
}

#------------------------------------------

=method delete UIDLS

Flag the specified message(s) to be deleted on the remote server.  The deletion
will take place on the moment that the connection is lost, whether this
is on purpose or not.

=cut

sub delete(@)
{   my $self = shift;

    my $server = $self->contactServer or return;

    $server->send(DELE => $self->uidl2seqnr($_))
       foreach @_;
}

#------------------------------------------

=method contactServer

Contact the server if the connection was lost, or has not been made yet.
When connecting fails, C<undef> is returned.  If the contact to the server
was still present, or could be established, an IO::Socket::INET is returned.

=cut

sub contactServer()
{   my $self = shift;

    my $server;
    if($server = $self->{MTP_server} && !$server->alive)
    {    undef $server;
         delete $self->{MTP_server};
         delete $self->{MTP_msgs};
         delete $self->{MTP_sizes};
    }

    return $server if defined $server;

    my ($interval, $retries, $timeout)   = $self->retry;
    my ($hostname, $port, $username, $password) = $self->remoteHost;

# Create a connection to the server and login.

    $server;
}

#------------------------------------------

=method disconnect

Break contact with the server, if that still exists.

=cut

sub disconnect()
{   my $self = shift;
}

#------------------------------------------

=method url

Represent this pop3 connection as URL.

=cut

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

#------------------------------------------

sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect;
}

#------------------------------------------

1;
