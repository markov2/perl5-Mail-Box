use strict;
use warnings;

package Mail::Transport::Sendmail;
use base 'Mail::Transport';

use Carp;

our $VERSION = 2.00_17;

=head1 NAME

Mail::Transport::Sendmail - transmit messages using external Sendmail program

=head1 CLASS HIERARCHY

 Mail::Transport::Sendmail
 is a Mail::Transport
 is a Mail::Reporter

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

The general methods for C<Mail::Transport::Sendmail> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MT send MESSAGE, OPTIONS
      new OPTIONS                       MR trace [LEVEL]
   MR report [LEVEL]                    MT trySend MESSAGE, OPTIONS

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
   MT findBinary NAME                   MR logSettings

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

sub trySend($@)
{   my ($self, $message, %args) = @_;

    if(open(MAILER, '|-')==0)
    {   my $program = $self->{MTM_program};
        { exec $program, '-t'; }
        $self->log(NOTICE => "Errors when closing $program: $!");
        return 0;
    }
 
    $message->print(\*MAILER);

    unless(close MAILER)
    {   $self->log(NOTICE => "Errors when closing sendmail: $!");
        $? ||= $!;
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

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
