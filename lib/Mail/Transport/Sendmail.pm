use strict;
use warnings;

package Mail::Transport::Sendmail;
use base 'Mail::Transport::Send';

use Carp;

=chapter NAME

Mail::Transport::Sendmail - transmit messages using external Sendmail program

=chapter SYNOPSIS

 my $sender = Mail::Transport::Sendmail->new(...);
 $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external C<'Sendmail'> program.
When instantiated, the mailer will look for the binary in specific system
directories, and the first version found is taken.

Some people use Postfix as MTA.  Postfix can be installed as replacement
for Sendmail: is provides a program with the same name and options.  So,
this module supports postfix as well.

=chapter METHODS

=c_method new %options

=default via C<'sendmail'>

=option  sendmail_options ARRAY
=default sendmail_options []
Add to the command-line of the started sendmail MTU a list of
separate words.  So say C< [ '-f', $file ] > and not C< [ "-f $file" ] >,
because the latter will be taken by sendmail as one word only.

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'sendmail';

    $self->SUPER::init($args) or return;

    $self->{MTS_program}
      = $args->{proxy}
     || $self->findBinary('sendmail')
     || return;

    $self->{MTS_opts} = $args->{sendmail_options} || [];
    $self;
}

#------------------------------------------

=section Sending mail

=method trySend $message, %options

=option  sendmail_options ARRAY
=default sendmail_options undef

=error Errors when closing sendmail mailer $program: $!
The was no problem starting the sendmail mail transfer agent, but for
some specific reason the message could not be handled correctly.

=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTS_program};
    if(open(MAILER, '|-')==0)
    {   my $options = $args{sendmail_options} || [];
        my @to = map {$_->address} $self->destinations($message, $args{to});

        # {} to avoid warning about code after exec
        {  exec $program, '-i', @{$self->{MTS_opts}}, @$options, @to; }

        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        exit 1;
    }
 
    $self->putContent($message, \*MAILER, undisclosed => 1);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing sendmail mailer $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

#------------------------------------------

1;
