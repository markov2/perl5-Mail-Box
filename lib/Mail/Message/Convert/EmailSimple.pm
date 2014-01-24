use strict;
use warnings;

package Mail::Message::Convert::EmailSimple;
use base 'Mail::Message::Convert';

use Mail::Internet;
use Mail::Header;
use Mail::Message;
use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;

use Email::Simple;
use Carp;

=chapter NAME

Mail::Message::Convert::EmailSimple - translate Mail::Message to Email::Simple vv

=chapter SYNOPSIS

 use Mail::Message::Convert::EmailSimple;
 my $convert = Mail::Message::Convert::EmailSimple->new;

 my Mail::Message $msg    = M<Mail::Message>->new;
 my Email::Simple $intern = $convert->export($msg);

 my Email::Simple $intern = M<Mail::Internet>->new;
 my Mail::Message $msg    = $convert->from($intern);

 use M<Mail::Box::Manager>;
 my $mgr     = Mail::Box::Manager->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($intern);

=chapter DESCRIPTION

The M<Email::Simple> class is one of the base objects used by the
large set of Email* modules, which implement many e-mail needs
which are also supported by MailBox.  You can use this class to
gradularly move from a Email* based implementation into a MailBox
implementation.

The internals of this class are far from optimal.  The conversion
does work (thanks to Ricardo Signes), but is expensive in time
and memory usage.  It could easily be optimized.

=chapter METHODS

=section Converting

=method export $message, %options
Returns a new M<Email::Simple> object based on the information from
a M<Mail::Message> object.  The $message specified is an
instance of a Mail::Message.

=examples
 my $convert = Mail::Message::Convert::EmailSimple->new;
 my Mail::Message  $msg   = M<Mail::Message>->new;
 my M<Mail::Internet> $copy  = $convert->export($msg);

=cut

sub export($@)
{   my ($thing, $message) = (shift, shift);

    croak "Export message must be a Mail::Message, but is a ".ref($message)."."
        unless $message->isa('Mail::Message');

    Email::Simple->new($message->string);
}

=method from $object, %options
Returns a new M<Mail::Message> object based on the information from
an M<Email::Simple>.

=examples
 my $convert = Mail::Message::Convert::EmailSimple->new;
 my Mail::Internet $msg  = M<Mail::Internet>->new;
 my M<Mail::Message>  $copy = $convert->from($msg);

=cut

sub from($@)
{   my ($thing, $email) = (shift, shift);

    croak "Converting from Email::Simple but got a ".ref($email).'.'
        unless $email->isa('Email::Simple');

    my $message = Mail::Message->read($email->as_string);
}

1;
