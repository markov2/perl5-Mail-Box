use strict;
use warnings;

package Mail::Transport::Qmail;
use base 'Mail::Transport::Send';

use Carp;

=head1 NAME

Mail::Transport::Qmail - transmit messages using external Qmail program

=head1 SYNOPSIS

 my $sender = Mail::Transport::Qmail->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external programs C<'qmail-inject'>,
part of the qmail mail-delivery system.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=default proxy 'qmail-inject'
=default via 'qmail'

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'qmail';

    $self->SUPER::init($args);

    $self->{MTM_program}
      = $args->{proxy}
     || $self->findBinary('qmail-inject', '/var/qmail/bin')
     || return;

    $self;
}

#------------------------------------------

=head2 Sending Mail

=cut

#------------------------------------------

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTM_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program; }
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        return 0;
    }
 
    $self->putContent($message, \*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

#------------------------------------------

1;
