use strict;
use warnings;

package Mail::Transport::Exim;
use base 'Mail::Transport::Send';

use Carp;

=head1 NAME

Mail::Transport::Exim - transmit messages using external Exim program

=head1 SYNOPSIS

 my $sender = Mail::Transport::Exim->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external C<'Exim'> program.
When instantiated, the mailer will look for the binary in specific system
directories, and the first version found is taken.

If you have Exim installed in a non-standard location, you will need to 
specify the path, using Mail::Transport::new(proxy)

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=default via 'exim'

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'exim';

    $self->SUPER::init($args) or return;

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('exim', '/usr/exim/bin')
     || return;

    $self;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $from = $args{from} || $message->sender;
    $from    = $from->address if $from->isa('Mail::Address');
    my @to   = map {$_->address} $self->destinations($message, $args{to});

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   { exec $program, '-f', $from, @to; }  # {} to avoid warning
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
