use strict;
use warnings;

package Mail::Transport::Qmail;
use base 'Mail::Transport::Send';

use Carp;

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::Qmail - transmit messages using external Qmail program

=head1 CLASS HIERARCHY

 Mail::Transport::Qmail
 is a Mail::Transport::Send
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $sender = Mail::Transport::Qmail->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Implements mail transport using the external programs C<'qmail-inject'>,
part of the qmail mail-delivery system.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT), L<Mail::Transport::Send> (MTS).

The general methods for C<Mail::Transport::Qmail> objects:

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
 timeout   Mail::Transport        <not used>
 trace     Mail::Reporter         'WARNINGS'
 username  Mail::Transport        <not used>
 via       Mail::Transport        'qmail'

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
