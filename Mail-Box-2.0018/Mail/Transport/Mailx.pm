use strict;
use warnings;

package Mail::Transport::Mailx;
use base 'Mail::Transport';

use Carp;

our $VERSION = 2.00_18;

=head1 NAME

Mail::Transport::Mailx - transmit messages using external mailx program

=head1 CLASS HIERARCHY

 Mail::Transport::Mailx
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $sender = Mail::Transport::Mailx->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external programs C<'mailx'>,
C<Mail>, or C<'mail'>.  When instantiated, the mailer will look for
any of these binaries in specific system directories, and the first
program found is taken.

Under Linux, freebsd, and bsdos the mail, Mail, and mailx names are
just links.  They are very primitive, what will cause many headers
to be lost.  For these platforms, you can better not use this
transport mechanism.

=head1 METHOD INDEX

The general methods for C<Mail::Transport::Mailx> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MT send MESSAGE, OPTIONS
      new OPTIONS                       MR trace [LEVEL]
   MR report [LEVEL]                    MT trySend MESSAGE, OPTIONS

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
   MT findBinary NAME [, DIRECTOR...    MR logSettings

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
   MT = L<Mail::Transport>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION       DESCRIBED IN       DEFAULT
 log          Mail::Reporter     'WARNINGS'
 proxy        Mail::Transport    undef
 trace        Mail::Reporter     'WARNINGS'
 via          Mail::Transport    <unused>

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MTM_program}
      = $args->{proxy}
     || $self->findBinary('mailx')
     || $self->findBinary('Mail')
     || $self->findBinary('mail')
     || return;

    $self;
}

#------------------------------------------

sub _try_send_bsdish($$)
{   my ($self, $message, $args) = @_;

    my ($to, $cc, $bcc);
    if(defined $message->get('Resent-Message-ID'))
    {   $to      = $message->get('Resent-To');
        $cc      = $message->get('Resent-Cc');
        $bcc     = $message->get('Resent-Bcc');
    }
    else
    {   $to      = $message->get('To');
        $cc      = $message->get('Cc');
        $bcc     = $message->get('Bcc');
    }

    my $subject = $message->get('Subject') || 'no subject';

    my (@to, @cc, @bcc);
    @to  = map {$_->address} Mail::Address->parse($to);
    @cc  = map {$_->address} Mail::Address->parse($cc)  if $cc;
    @bcc = map {$_->address} Mail::Address->parse($bcc) if $bcc;

    my @options = ('-s' => $subject);

    {   local $" = ',';
        push @options, ('-c' => "@cc")  if @cc;
        push @options, ('-b' => "@bcc") if @bcc;
    }

    my $program = $self->{MTM_program};
    if((open MAILER, '|-')==0)
    {   close STDOUT;
        { exec $program, @options, @to; }
        $self->log(NOTICE => "Cannot start contact to $program: $!");
        return 0;
    }
 
    $message->body->print(\*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Sending via $program failed: $! ($?)");
        return 0;
    }

    1;
}

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $os = $^O;
    return $self->_try_send_bsdish($message, \%args)
        if $os eq 'linux' || $os eq 'freebsd' || $os eq 'bsdos';

    my $program = $self->{MTM_program};
    unless(open(MAILER, '|-', $program, '-t'))
    {   $self->log(NOTICE => "Cannot start contact to $program: $!");
        return 0;
    }
 
    $message->print(\*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Sending via $program failed: $! ($?)");
        return 0;
    }

    1;
}

#------------------------------------------

#=back
#
#=head1 METHODS for extension writers
#
#=over 4
#
#=cut

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
