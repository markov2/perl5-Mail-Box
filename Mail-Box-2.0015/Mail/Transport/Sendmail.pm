use strict;
use warnings;

package Mail::Transport::Sendmail;
use base 'Mail::Transport';

use Carp;

our $VERSION = 2.00_15;

=head1 NAME

Mail::Transport::Sendmail - transmit messages using external Sendmail program

=head1 SYNOPSIS

 my $sender = Mail::Transport::Sendmail->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external programs C<'Sendmail'>,
C<Mail>, or C<'mail'>.  When instantiated, the mailer will look for
any of these binaries in specific system directories, and the first
program found is taken.

Under Linux, freebsd, and bsdos the mail, Mail, and Sendmail names are
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

    my $program = $self->findBinary('sendmail');
    return unless defined $program;

    $self->{MTM_program} = $program;
    $self;
}

#------------------------------------------

sub send($@)
{   my ($self, $message, %args) = @_;

    if(open(MAILER, '|-')==0)
    {   exec $self->{MTM_program}, '-t';
    }
 
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
