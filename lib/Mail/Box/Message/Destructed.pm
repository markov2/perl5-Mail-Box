#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Message::Destructed;
use parent 'Mail::Box::Message';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error/ ];

#--------------------
=chapter NAME

Mail::Box::Message::Destructed - a destructed message

=chapter SYNOPSIS

  $folder->message(3)->destruct;

=chapter DESCRIPTION

When a message folder is read, each message will be parsed into Perl
structures.  Especially the header structure can consume a huge amount
of memory (message bodies can be moved to external temporary files).
Destructed messages have forcefully cleaned-up all header and body
information, and are therefore much smaller.  Some useful information
is still in the object.

BE WARNED: once a message is destructed, it cannot be revived.  Destructing
enforces irreversable deletion from the folder.  If you have a folder opened
for read-only, the message will stay in that folder, but otherwise it may
be deleted.

=chapter METHODS

=c_method new $msgid, %options
You cannot instantiate a destructed message object.  Destruction is
done by calling M<Mail::Box::Message::destruct()>.

=error you cannot instantiate a destructed message.
You cannot instantiate a destructed message object directly.  Destruction
is done by calling M<Mail::Box::Message::destruct()> on any existing
folder message.

=cut

sub new(@) { error __x"you cannot instantiate a destructed message." }

sub isDummy()    { 1 }

=method head [$head]
When undef is specified for $head, no change has to take place and
the method returns silently.  In all other cases, this method will
complain that the header has been removed.

=error You cannot take the head/body of a destructed message
The message originated from a folder, but its memory has been freed-up
forcefully by means of M<Mail::Box::Message::destruct()>.  Apparently,
your program still tries to get to the header or body data after this
destruction, which is not possible.

=error you cannot take the head of a destructed message.
=error you cannot set the head on a destructed message.
=cut

sub head(;$)
{	my ($self, $head) = @_;
	@_==1 and error __x"you cannot take the head of a destructed message.";
	defined $head and error __x"you cannot set the head on a destructed message.";
	undef;
}

=method body [$body]
When undef is specified for $body, no change has to take place and
the method returns silently.  In all other cases, this method will
complain that the body data has been removed.

=error you cannot take the body of a destructed message.
=error you cannot set the body on a destructed message.
=cut

sub body(;$)
{	my ($self, $body) = @_;
	@_==1 and error __x"you cannot take the body of a destructed message.";
	defined $body and error __x"you cannot set the body on a destructed message.";
	undef;
}

=c_method coerce $message
Coerce a Mail::Box::Message into destruction.

=examples of coercion to death

  Mail::Box::Message::Destructed->coerce($folder->message(1));
  $folder->message(1)->destruct;  # same

  my $msg = $folder->message(1);
  Mail::Box::Message::Destructed->coerce($msg);
  $msg->destruct;                 # same

=error you cannot coerce a $class into destruction.
Only real Mail::Box::Message objects can get destructed into
Mail::Box::Message::Destructed objects.  Mail::Message free
their memory immediately when the last reference is lost.
=cut

sub coerce($)
{	my ($class, $message) = @_;

	$message->isa('Mail::Box::Message')
		or error __x"you cannot coerce a {class} into destruction.", class => ref $message;

	$message->body(undef);
	$message->head(undef);
	$message->modified(0);

	bless $message, $class;
}

=method modified [$flag]
=error you cannot set the modified flag on a destructed message.
=cut

sub modified(;$)
{	my $self = shift;

	! @_ || ! $_[0]
		or error __x"you cannot set the modified flag on a destructed message.";

	0;
}

sub isModified() { 0 }

=method label $label|PAIRS
It is possible to delete a destructed message, but not to undelete it.

=error destructed message has no labels except 'deleted', requested is $label.
=error destructed message has no labels except 'deleted', trying to set @labels.

=error destructed message can not be undeleted
Once a message is destructed, it can not be revived.  Destruction is an
optimization in memory usage: if you need an undelete functionality, then
you can not use M<Mail::Box::Message::destruct()>.
=cut

sub label($;@)
{	my $self = shift;

	if(@_==1)
	{	my $label = shift;
		return $self->SUPER::label('deleted') if $label eq 'deleted';

		error __x"destructed message has no labels except 'deleted', requested is {label}.", label => $label;
	}

	my %flags = @_;
	keys %flags==1 && exists $flags{deleted}
		or error __x"destructed message has no labels except 'deleted', trying to set {labels}.", labels => [keys %flags];

	$flags{deleted}
		or error __x"destructed message can not be undeleted.";

	1;
}

sub labels() { wantarray ? ('deleted') : +{deleted => 1} }

1;
