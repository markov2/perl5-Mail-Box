
use strict;

package Mail::Message::Dummy;

use base 'Mail::Message';
use Carp;

our $VERSION = '2.00_01';

=head1 NAME

Mail::Message::Dummy - Fill-up a missing message in a list.

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Box::Manager> and C<Mail::Message> first.

Dummy messages are used by modules which maintain ordered lists
of messages, usually based on message-id.  A good example is
C<Mail::Box::Threads>, which detects related messages by scanning
the known message-headers for references to other messages.  As
long as the referred messages are not found for real inside the
mailbox, their place is occupied by a dummy.

Be careful that, when you use modules which may create dummies, that
you check for them in your messages (using C<isDummy()>) before
trying to reach the header or body.

=head1 METHODS

A dummy can store the same information as a real C<Mail::Box::Message>,
except that it will croak on the moment header or body information is
required.

=over 4

#-------------------------------------------

=item new

(Class method) Create a new dummy message.

Examples:

    my $message = Mail::Box::Message::Dummy->new($msgid);
    if($message->isDummy) {...}

=cut

sub new($) { shift->SUPER::new(messageID => shift, deleted => 1) }
 
sub isDummy() { 1 }

sub shortSize($) {"   0"};

sub shortString()
{   my Mail::Box::Message $self = shift;
    sprintf "----(%2d) <not found>";
}


=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_01

=cut

1;
