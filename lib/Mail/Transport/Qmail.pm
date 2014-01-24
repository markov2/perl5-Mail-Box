use strict;
use warnings;

package Mail::Transport::Qmail;
use base 'Mail::Transport::Send';

use Carp;

=chapter NAME

Mail::Transport::Qmail - transmit messages using external Qmail program

=chapter SYNOPSIS

 my $sender = Mail::Transport::Qmail->new(...);
 $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external programs C<'qmail-inject'>,
part of the qmail mail-delivery system.

=chapter METHODS

=c_method new %options

=default proxy C<'qmail-inject'>
=default via C<'qmail'>

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'qmail';

    $self->SUPER::init($args) or return;

    $self->{MTM_program}
      = $args->{proxy}
     || $self->findBinary('qmail-inject', '/var/qmail/bin')
     || return;

    $self;
}

#------------------------------------------

=method trySend $message, %options

=error Errors when closing Qmail mailer $program: $!

The Qmail mail transfer agent did start, but was not able to handle the
message for some specific reason.

=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTM_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program; }
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        exit 1;
    }
 
    $self->putContent($message, \*MAILER, undisclosed => 1);

    unless(close MAILER)
    {   $self->log(ERROR => "Errors when closing Qmail mailer $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

#------------------------------------------

1;
