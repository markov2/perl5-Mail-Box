use strict;
use warnings;

package Mail::Transport::Send;
use base 'Mail::Transport';

use Carp;
use File::Spec;
use Errno 'EAGAIN';

our $VERSION = 2.018;

=head1 NAME

Mail::Transport::Send - send a message

=head1 CLASS HIERARCHY

 Mail::Transport::Send
 is a Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $message = Mail::Message->new(...);

 # Some extensions implement sending:
 $message->send;
 $message->send(via => 'sendmail');

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Send a message to the destinations as specified in the header.  The
C<Mail::Transport::Send> module is capable of autodetecting which of the
following modules work on your system; you may simply call C<send>
without C<via> options to get a message transported.

=over 4

=item * C<Mail::Transport::Sendmail>

Use sendmail to process and deliver the mail.  This requires the
C<sendmail> program to be installed on your system.

=item * C<Mail::Transport::Qmail>

Use C<qmail-inject> to distribute the message.

=item * C<Mail::Transport::SMTP>

In this case, Perl is handling mail transport on its own.  This is less
desired but more portable than sending with sendmail or qmail.

The advantage is that this sender is environment independent, and easier to
configure.  However, there is no daemon involved which means that your
program will wait until the message is delivered, and the message is
lost when your program is interrupted during delivery (which may
take hours to complete).

=item * C<Mail::Transport::Mailx>

Use the external C<mail>, C<mailx>, or C<Mail> programs to send the
message.  Usually, the result is poor, because some versions of these
programs do not support MIME headers.

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Transport> (MT).

The general methods for C<Mail::Transport::Send> objects:

   MR errors                               send MESSAGE, OPTIONS
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                          trySend MESSAGE, OPTIONS
   MR report [LEVEL]                    MR warnings
   MR reportAll [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
   MT findBinary NAME [, DIRECTOR...       putContent MESSAGE, FILEHAN...
   MR inGlobalDestruction               MT remoteHost
   MR logPriority LEVEL                 MT retry

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN       DEFAULT
 hostname          Mail::Transport    'localhost'
 interval          Mail::Transport    30
 log               Mail::Reporter     'WARNINGS'
 password          Mail::Transport    undef
 proxy             Mail::Transport    undef
 retry             Mail::Transport    undef
 timeout           Mail::Transport    120
 trace             Mail::Reporter     'WARNINGS'
 username          Mail::Transport    undef
 via               Mail::Transport    'sendmail'

=cut

sub new(@)
{   my $class = shift;
    $class->SUPER::new(via => 'sendmail', @_);
}

#------------------------------------------

=item send MESSAGE, OPTIONS

Transmit the MESSAGE, which may be anything what can be coerced into a
C<Mail::Message>, so including C<Mail::Internet> and C<MIME::Entity>
messages.  It returns true when the transmission was succesfully completed.

As OPTIONS, you can specify an C<interval> and a C<retry> count, which
will overrule the setting at initiation of the transporter object.

=cut

sub send($@)
{   my ($self, $message) = (shift, shift);

    unless($message->isa('Mail::Message'))  # avoid rebless.
    {   $message = Mail::Message->coerce($message);
        confess "Unable to coerce object into Mail::Message."
            unless defined $message;
    }

    return 1 if $self->trySend($message);
    return 0 unless $?==EAGAIN;

    my %args     = @_;
    my ($interval, $retry) = $self->retry;
    $interval = $args{interval} if exists $args{interval};
    $retry    = $args{retry}    if exists $args{retry};

    while($retry!=0)
    {   sleep $interval;
        return 1 if $self->trySend($message);
        return 0 unless $?==EAGAIN;
        $retry--;
    }

    0;
}

#------------------------------------------

=item trySend MESSAGE, OPTIONS

Try to send the message. This will return true if successful, and
false in case some problems where detected.  The C<$?> contains
the exit status of the command which was started.

=cut

sub trySend($@)
{   my $self = shift;
    $self->log(ERROR => "Transporters of type ".ref($self). " cannot send.");
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item putContent MESSAGE, FILEHANDLE, OPTIONS

Print the content of the MESSAGE to the FILEHANDLE.

 OPTIONS           DESCRIBED IN         DEFAULT
 body_only         Mail::Transport      <false>
 undisclosed       Mail::Transport      <false>

=over 4

=item * body_only =E<gt> BOOLEAN

Print only the body of the message, not the whole.

=item * undisclosed =E<gt> BOOLEAN

Do not print the C<Bcc> and C<Resent-Bcc> lines.  Default false, which
means that they are printed.

=back

=cut

sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only})   { $message->body->print($fh) }
    elsif($args{undisclosed})
    {    $message->head->printUndisclosed($fh);
         $message->body->print($fh);
    }
    else                      { $message->Mail::Message::print($fh) }

    $self;
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
