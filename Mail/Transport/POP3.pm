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

=method url

Represent this pop3 connection as URL.

=cut

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

#------------------------------------------

=method top UIDL, [MAXLINES]

Returns a reference to an array which contains the header of the message
with the specified UIDL.  The optional integer MAXLINES specifies the
number of lines from the body which are wanted: by default all.

=cut

sub top($;$)
{   my ($self, $uidl, $ask) = (shift, shift);
    undef;
}

#------------------------------------------

=method contactServer

=cut

sub contactServer()
{   my $self = shift;

    my ($interval, $retries, $timeout)   = $self->retry;
    my ($hostname, $port, $username, $password) = $self->remoteHost;
}

#------------------------------------------

1;
