use strict;
use warnings;

package Mail::Transport::Send;
use base 'Mail::Transport';

use Carp;
use File::Spec;
use Errno 'EAGAIN';

=head1 NAME

Mail::Transport::Send - send a message

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

=item * Mail::Transport::Sendmail

Use sendmail to process and deliver the mail.  This requires the
C<sendmail> program to be installed on your system.  Whether this
is an original sendmail, or a replacement from Postfix does matter.

=item * Mail::Transport::Exim

Use C<exim> to distribute the message.

=item * Mail::Transport::Qmail

Use C<qmail-inject> to distribute the message.

=item * Mail::Transport::SMTP

In this case, Perl is handling mail transport on its own.  This is less
desired but more portable than sending with sendmail or qmail.

The advantage is that this sender is environment independent, and easier to
configure.  However, there is no daemon involved which means that your
program will wait until the message is delivered, and the message is
lost when your program is interrupted during delivery (which may
take hours to complete).

=item * Mail::Transport::Mailx

Use the external C<mail>, C<mailx>, or C<Mail> programs to send the
message.  Usually, the result is poor, because some versions of these
programs do not support MIME headers.  Besides, these programs are
known to have exploitable security breaches.

=back

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=default via 'sendmail'

=cut

sub new(@)
{   my $class = shift;
    $class->SUPER::new(via => 'sendmail', @_);
}

#------------------------------------------

=head2 Sending Mail

=cut

#------------------------------------------

=method send MESSAGE, OPTIONS

Transmit the MESSAGE, which may be anything what can be coerced into a
Mail::Message, so including Mail::Internet and MIME::Entity
messages.  It returns true when the transmission was successfully completed.

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

=method trySend MESSAGE, OPTIONS

Try to send the message. This will return true if successful, and
false in case some problems where detected.  The C<$?> contains
the exit status of the command which was started.

=cut

sub trySend($@)
{   my $self = shift;
    $self->log(ERROR => "Transporters of type ".ref($self). " cannot send.");
}

#------------------------------------------

=method putContent MESSAGE, FILEHANDLE, OPTIONS

Print the content of the MESSAGE to the FILEHANDLE.

=option  body_only BOOLEAN
=default body_only <false>

Print only the body of the message, not the whole.

=option  undisclosed BOOLEAN
=default undisclosed <false>

Do not print the C<Bcc> and C<Resent-Bcc> lines.  Default false, which
means that they are printed.

=cut

sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only}) { $message->body->print($fh) }
    elsif($args{undisclosed})
    {    $message->head->printUndisclosed($fh);
         $message->body->print($fh);
    }
    else { $message->Mail::Message::print($fh) }

    $self;
}

#------------------------------------------

1;
