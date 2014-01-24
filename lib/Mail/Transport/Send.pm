use strict;
use warnings;

package Mail::Transport::Send;
use base 'Mail::Transport';

use Carp;
use File::Spec;
use Errno 'EAGAIN';

=chapter NAME

Mail::Transport::Send - send a message

=chapter SYNOPSIS

 my $message = Mail::Message->new(...);

 # Some extensions implement sending:
 $message->send;
 $message->send(via => 'sendmail');

 my $sender = M<Mail::Transport::SMTP>->new(...);
 $sender->send($message);

=chapter DESCRIPTION

Send a message to the destinations as specified in the header.  The
C<Mail::Transport::Send> module is capable of autodetecting which of the
following modules work on your system; you may simply call C<send>
without C<via> options to get a message transported.

=over 4

=item * M<Mail::Transport::Sendmail>

Use sendmail to process and deliver the mail.  This requires the
C<sendmail> program to be installed on your system.  Whether this
is an original sendmail, or a replacement from Postfix does matter.

=item * M<Mail::Transport::Exim>

Use C<exim> to distribute the message.

=item * M<Mail::Transport::Qmail>

Use C<qmail-inject> to distribute the message.

=item * M<Mail::Transport::SMTP>

In this case, Perl is handling mail transport on its own.  This is less
desired but more portable than sending with sendmail or qmail.
The advantage is that this sender is environment independent, and easier to
configure.  However, there is no daemon involved which means that your
program will wait until the message is delivered, and the message is
lost when your program is interrupted during delivery (which may
take hours to complete).

=item * M<Mail::Transport::Mailx>

Use the external C<mail>, C<mailx>, or C<Mail> programs to send the
message.  Usually, the result is poor, because some versions of these
programs do not support MIME headers.  Besides, these programs are
known to have exploitable security breaches.

=back

=chapter METHODS

=c_method new %options

=default via C<'sendmail'>

=cut

sub new(@)
{   my $class = shift;
    return $class->SUPER::new(@_)
       if $class ne __PACKAGE__;

    require Mail::Transport::Sendmail;
    Mail::Transport::Sendmail->new(@_);
}

#------------------------------------------

=section Sending mail

=method send $message, %options

Transmit the $message, which may be anything what can be coerced into a
M<Mail::Message>, so including M<Mail::Internet> and M<MIME::Entity>
messages.  It returns true when the transmission was successfully completed.

=option  interval SECONDS
=default interval M<new(interval)>

=option  retry INTEGER
=default retry M<new(retry)>

=option  to STRING
=default to C<undef>
Overrules the destination(s) of the message, which is by default taken
from the (Resent-)To, (Resent-)Cc, and (Resent-)Bcc.

=cut

sub send($@)
{   my ($self, $message, %args) = @_;

    unless($message->isa('Mail::Message'))  # avoid rebless.
    {   $message = Mail::Message->coerce($message);
        confess "Unable to coerce object into Mail::Message."
            unless defined $message;
    }

    return 1 if $self->trySend($message, %args);
    return 0 unless $?==EAGAIN;

    my ($interval, $retry) = $self->retry;
    $interval = $args{interval} if exists $args{interval};
    $retry    = $args{retry}    if exists $args{retry};

    while($retry!=0)
    {   sleep $interval;
        return 1 if $self->trySend($message, %args);
        return 0 unless $?==EAGAIN;
        $retry--;
    }

    0;
}

#------------------------------------------

=method trySend $message, %options

Try to send the message. This will return true if successful, and
false in case some problems where detected.  The C<$?> contains
the exit status of the command which was started.

=error Transporters of type $class cannot send.

The M<Mail::Transport> object of the specified type can not send messages,
but only receive message.

=cut

sub trySend($@)
{   my $self = shift;
    $self->log(ERROR => "Transporters of type ".ref($self). " cannot send.");
}

#------------------------------------------

=method putContent $message, $fh, %options

Print the content of the $message to the $fh.

=option  body_only BOOLEAN
=default body_only <false>

Print only the body of the message, not the whole.

=option  undisclosed BOOLEAN
=default undisclosed <false>

Do not print the C<Bcc> and C<Resent-Bcc> lines.  Default false, which
means that they are not printed.

=cut

sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only})   { $message->body->print($fh) }
    elsif($args{undisclosed}) { $message->Mail::Message::print($fh) }
    else
    {   $message->head->printUndisclosed($fh);
        $message->body->print($fh);
    }

    $self;
}

#------------------------------------------

=method destinations $message, [$address|ARRAY]

Determine the destination for this message.  If a valid $address is defined,
this is used to overrule the addresses within the message.  If the $address
is C<undef> it is ignored.  It may also be an ARRAY of addresses.

If no $address is specified, the message is scanned for resent groups
(see M<Mail::Message::Head::Complete::resentGroups()>).  The addresses
found in the first (is latest added) group are used.  If no resent groups
are found, the normal C<To>, C<Cc>, and C<Bcc> lines are taken.

=warning Resent group does not specify a destination
The message which is sent is the result of a bounce (for instance
created with M<Mail::Message::bounce()>), and therefore starts with a
C<Received> header field.  With the C<bounce>, the new destination(s)
of the message are given, which should be included as C<Resent-To>,
C<Resent-Cc>, and C<Resent-Bcc>.

The C<To>, C<Cc>, and C<Bcc> header information is only used if no
C<Received> was found.  That seems to be the best explanation of the RFC.

As alternative, you may also specify the C<to> option to some of the senders
(for instance M<Mail::Transport::SMTP::send(to)> to overrule any information
found in the message itself about the destination.

=warning Message has no destination
It was not possible to figure-out where the message is intended to go
to.

=cut

sub destinations($;$)
{   my ($self, $message, $overrule) = @_;
    my @to;

    if(defined $overrule)      # Destinations overruled by user.
    {   my @addr = ref $overrule eq 'ARRAY' ? @$overrule : ($overrule);
        @to = map { ref $_ && $_->isa('Mail::Address') ? ($_)
                    : Mail::Address->parse($_) } @addr;
    }
    elsif(my @rgs = $message->head->resentGroups)
    {   @to = $rgs[0]->destinations;
        $self->log(WARNING => "Resent group does not specify a destination"), return ()
            unless @to;
    }
    else
    {   @to = $message->destinations;
        $self->log(WARNING => "Message has no destination"), return ()
            unless @to;
    }

    @to;
}

#------------------------------------------

=section Server connection

=section Error handling

=cut

1;
