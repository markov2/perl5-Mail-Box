
use strict;

package Mail::Message::Dummy;
use base 'Mail::Message';

use Carp;

=chapter NAME

Mail::Message::Dummy - a placeholder for a missing messages

=chapter SYNOPSIS

=chapter DESCRIPTION

Dummy messages are used by modules which maintain ordered lists
of messages, usually based on message-id.  A good example is
M<Mail::Box::Thread::Manager>, which detects related messages by
scanning the known message headers for references to other messages.
As long as the referenced messages are not found inside the mailbox,
their place is occupied by a dummy.

Be careful when using modules which may create dummies.  Before trying to
access the header or body use M<isDummy()> to check if the message is a
dummy message.

=chapter METHODS

=c_method new $message_id, %options

Create a new dummy message to occupy the space for
a real message with the specified $message_id.

=default body <not used>
=default field_type <not used>
=default head <not used>
=default head_type <not used>
=default messageId <required>
=default modified <always false>
=default trusted <always true>

=examples

 my $message = Mail::Message::Dummy->new($msgid);
 if($message->isDummy) {...}

=error Message-Id is required for a dummy.

A dummy message occupies the place for a real message.  When a dummy is created,
the id of the message which place it is holding must be known.

=cut

sub init($)
{   my ($self, $args) = @_;

    @$args{ qw/modified trusted/ } = (0, 1);
    $self->SUPER::init($args);

    $self->log(ERROR => "Message-Id is required for a dummy.")
       unless exists $args->{messageId};

    $self;
}
 
#-------------------------------------------

sub isDummy()    { 1 }

=method head ...

=error You cannot take the head/body of a dummy message
Dummy messages are place-holders in message threads: the thread detected
the existence of the message, because it found the message-id in a
Reply-To or References field, however it did not find the header and
body of the message yet.  Use M<isDummy()> to check whether the thread
node returned a dummy or not.

=cut

sub head()
{    shift->log(ERROR => "You cannot take the head of a dummy message");
     ();
}

sub body()
{    shift->log(ERROR => "You cannot take the body of a dummy message");
     ();
}

1;
