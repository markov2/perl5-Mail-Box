
use strict;

package Mail::Message::Dummy;
use base 'Mail::Message';

use Carp;

=head1 NAME

Mail::Message::Dummy - a placeholder for a missing messages

=head1 SYNOPSIS

=head1 DESCRIPTION

Dummy messages are used by modules which maintain ordered lists of
messages, usually based on message-id.  A good example is
Mail::Box::Thread::Manager, which detects related messages by scanning the
known message headers for references to other messages.  As long as the
referenced messages are not found inside the mailbox, their place is
occupied by a dummy.

Be careful when using modules which may create dummies.  Before trying to
access the header or body use isDummy() to check if the message is a
dummy message.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new MESSAGE-ID, OPTIONS

(Class method) Create a new dummy message to occupy the space for
a real message with the specified MESSAGE-ID.

=default body <not used>
=default field_type <not used>
=default head <not used>
=default head_type <not used>
=default log 'WARNINGS'
=default messageId <required>
=default modified <always false>
=default trace 'WARNINGS'
=default trusted <always true>

=examples

 my $message = Mail::Message::Dummy->new($msgid);
 if($message->isDummy) {...}

=cut

sub init($)
{   my ($self, $args) = @_;

    @$args{ qw/modified trusted/ } = (0, 1);
    $self->SUPER::init($args);

    $self->log(ERROR => "MessageId is required for a dummy.")
       unless exists $args->{messageId};

    $self;
}
 
#-------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

sub isDummy()    { 1 }

#-------------------------------------------

=head2 The Header

=cut

sub head()
{    shift->log(INTERNAL => "You cannot take the head of a dummy");
     ();
}

#-------------------------------------------

=head2 The Body

=cut

#-------------------------------------------

sub body()
{    shift->log(INTERNAL => "You cannot take the body of a dummy");
     ();
}

#-------------------------------------------

1;
