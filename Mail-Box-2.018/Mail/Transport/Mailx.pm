use strict;
use warnings;

package Mail::Transport::Mailx;
use base 'Mail::Transport::Send';

use Carp;

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::Mailx - transmit messages using external mailx program

=head1 CLASS HIERARCHY

 Mail::Transport::Mailx
 is a Mail::Transport::Send
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

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT), L<Mail::Transport::Send> (MTS).

The general methods for C<Mail::Transport::Mailx> objects:

   MR errors                           MTS send MESSAGE, OPTIONS
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                      MTS trySend MESSAGE, OPTIONS
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

 OPTION    DESCRIBED IN           DEFAULT
 hostname  Mail::Transport        <not used>
 interval  Mail::Transport        30
 log       Mail::Reporter         'WARNINGS'
 password  Mail::Transport        <not used>
 proxy     Mail::Transport        <autodetect>
 retry     Mail::Transport        undef
 style     Mail::Transport::Mailx <autodetect>
 trace     Mail::Reporter         'WARNINGS'
 timeout   Mail::Transport        <not used>
 username  Mail::Transport        <not used>
 via       Mail::Transport        'mailx'

=over 4

=item * style =<gt> 'BSD'|'RFC822'

There are two version of the C<mail> program.  The newest accepts
RFC822 messages, and automagically collect information about where
the message is to be send to.  The BSD style mail command predates
MIME, and expects lines which start with a '~' (tilde) to specify
destinations and such.  This field is autodetect, however on some
platforms both versions of C<mail> can live (like verious Linux
distributions).

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{via} = 'mailx';

    $self->SUPER::init($args);

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
        return 0;
    }
 
    $self->putContent($message, \*MAILER, body_only => 1);

    my $msgid = $message->messageId;

    if(close MAILER) { $self->log(PROGRESS => "Message $msgid send.") }
    else
    {   $self->log(NOTICE =>
            "Sending message $msgid via $program failed: $! ($?)");
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
    {   $self->log(NOTICE => "Sending via $program failed: $! ($?)");
        return 0;
    }

    1;
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
