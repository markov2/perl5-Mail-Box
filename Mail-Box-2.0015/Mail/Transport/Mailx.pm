use strict;
use warnings;

package Mail::Transport::Mailx;
use base 'Mail::Transport';

use Carp;

our $VERSION = 2.00_15;

=head1 NAME

Mail::Transport::Mailx - transmit messages using external mailx program

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

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION       DESCRIBED IN       DEFAULT
 log          Mail::Reporter     'WARNINGS'
 trace        Mail::Reporter     'WARNINGS'
 via          Mail::Transport    <unused>

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my ($command, $program);
    foreach ( qw/mailx mail/ )
    {   if($program = $self->findBinary($_))
        {   $command = $_;
            last;
        }
    }

    return undef unless defined $program;

    $self->{MTM_program} = $program;
    $self;
}

#------------------------------------------

sub _send_bsdish($$)
{   my ($self, $message, $args) = @_;
    my $to      = $message->get('to');
    my $cc      = $message->get('cc');
    my $bcc     = $message->get('bcc');
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

    if((open MAILER, '|-')==0)
    {   close STDOUT;
        exec $self->{MTM_program}, @options, @to;
    }
 
    $message->body->print(\*MAILER);

    unless(close MAILER)
    {   carp "Transmission via $self->{MTM_program} interrupted: $!";
        return;
    }

    $message;
}

sub send($@)
{   my ($self, $message, %args) = @_;

    my $os = $^O;
    return $self->_send_bsdish($message, \%args)
        if $os eq 'linux' || $os eq 'freebsd' || $os eq 'bsdos';

    return
        unless open(MAILER, '| $self->{MTM_program} -t');
 
    $message->print(\*MAILER);

    unless(close MAILER)
    {   carp "Transmission via $self->{MTM_program} interrupted: $!";
        return;
    }

    $message;
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

This code is beta, version 2.00_15.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
