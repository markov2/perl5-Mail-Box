
use strict;

package Mail::Message::Dummy;

use base 'Mail::Message';
use Carp;

our $VERSION = '2.00_03';

=head1 NAME

Mail::Message::Dummy - A placeholder for a missing message in a list.

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Box-Overview> first.

Dummy messages are used by modules which maintain ordered lists of
messages, usually based on message-id.  A good example is
C<Mail::Box::Threads>, which detects related messages by scanning the
known message headers for references to other messages.  As long as the
referenced messages are not found inside the mailbox, their place is
occupied by a dummy.

Be careful when using modules which may create dummies.  Before trying to
access the header or body use C<isDummy()> to check if the message is a
dummy message.

=head1 METHODS

A dummy can store the same information as a real C<Mail::Box::Message>,
except that it will croak at the moment header or body information is
accessed.

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

This code is beta, version 2.00_03

=cut

1;
