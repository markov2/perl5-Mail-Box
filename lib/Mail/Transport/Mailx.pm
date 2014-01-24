use strict;
use warnings;

package Mail::Transport::Mailx;
use base 'Mail::Transport::Send';

use Carp;

=chapter NAME

Mail::Transport::Mailx - transmit messages using external mailx program

=chapter SYNOPSIS

 my $sender = Mail::Transport::Mailx->new(...);
 $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external programs C<'mailx'>,
C<Mail>, or C<'mail'>.  When instantiated, the mailer will look for
any of these binaries in specific system directories, and the first
program found is taken.

B<WARNING: There are many security issues with mail and mailx. DO NOT USE
these commands to send messages which contains data derived from any
external source!!!>

Under Linux, freebsd, and bsdos the C<mail>, C<Mail>, and C<mailx> names are
just links to the same binary.  The implementation is very primitive, pre-MIME
standard,  what may cause many headers to be lost.  For these platforms (and
probably for other platforms as well), you can better not use this transport
mechanism.

=chapter METHODS

=c_method new %options

=default via   C<'mailx'>

=option  style 'BSD'|'RFC822'
=default style <autodetect>

There are two version of the C<mail> program.  The newest accepts
RFC822 messages, and automagically collect information about where
the message is to be send to.  The BSD style mail command predates
MIME, and expects lines which start with a C<'~'> (tilde) to specify
destinations and such.  This field is autodetect, however on some
platforms both versions of C<mail> can live (like various Linux
distributions).

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'mailx';

    $self->SUPER::init($args) or return;

    $self->{MTM_program}
      = $args->{proxy}
     || $self->findBinary('mailx')
     || $self->findBinary('Mail')
     || $self->findBinary('mail')
     || return;

    $self->{MTM_style}
      = defined $args->{style}                       ? $args->{style}
      : $^O =~ m/linux|freebsd|bsdos|netbsd|openbsd/ ? 'BSD'
      :                                                'RFC822';

    $self;
}

#------------------------------------------

=method trySend $message, %options

=error Sending via mailx mailer $program failed: $! ($?)

Mailx (in some shape: there are many different implementations) did start
accepting messages, but did not succeed sending it.

=cut

sub _try_send_bsdish($$)
{   my ($self, $message, $args) = @_;

    my @options = ('-s' => $message->subject);

    {   local $" = ',';
        my @cc  = map {$_->format} $message->cc;
        push @options, ('-c' => "@cc")  if @cc;

        my @bcc = map {$_->format} $message->bcc;
        push @options, ('-b' => "@bcc") if @bcc;
    }

    my @to      = map {$_->format} $message->to;
    my $program = $self->{MTM_program};

    if((open MAILER, '|-')==0)
    {   close STDOUT;
        { exec $program, @options, @to }
        $self->log(NOTICE => "Cannot start contact to $program: $!");
        exit 1;
    }
 
    $self->putContent($message, \*MAILER, body_only => 1);

    my $msgid = $message->messageId;

    if(close MAILER) { $self->log(PROGRESS => "Message $msgid send.") }
    else
    {   $self->log(ERROR => "Sending via mailx mailer $program failed: $! ($?)");
        return 0;
    }

    1;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    return $self->_try_send_bsdish($message, \%args)
        if $self->{MTM_style} eq 'BSD';

    my $program = $self->{MTM_program};
    unless(open MAILER, '|-', $program, '-t')
    {   $self->log(NOTICE => "Cannot start contact to $program: $!");
        return 0;
    }
 
    $self->putContent($message, \*MAILER);

    unless(close MAILER)
    {   $self->log(ERROR => "Sending via mailx mailer $program failed: $! ($?)");
        return 0;
    }

    1;
}

#------------------------------------------

1;
