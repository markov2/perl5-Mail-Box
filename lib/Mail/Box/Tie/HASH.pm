#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Tie::HASH;
use parent 'Mail::Box::Tie';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x warning/ ];

#--------------------
=chapter NAME

Mail::Box::Tie::HASH - access an existing message folder as a hash

=chapter SYNOPSIS

  tie my(%inbox), 'Mail::Box::Tie::HASH', $folder;

  foreach my $msgid (keys %inbox)
  {   print $inbox{$msgid};
      delete $inbox{$msgid};
  }

  $inbox{$msg->messageId} = $msg;

=chapter DESCRIPTION

Certainly when you look at a folder as being a set of related messages
based on message-id, it is logical to access the folder through a hash.

For a tied hash, the message-id is used as the key.  The message-id is usually
unique, but when two or more instances of the same message are in the same
folder, one will be flagged for deletion and the other will be returned.

This implementation uses basic folder access routines which are related
to the message-id.

=chapter METHODS

=section Constructors

=tie %hash 'Mail::Box::Tie::HASH', FOLDER
Connects the FOLDER object to a HASH.

=example
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open(access => 'rw');
  tie my(%inbox), 'Mail::Box::Tie::HASH', $folder;
=cut

sub TIEHASH(@)
{	my ($class, $folder) = @_;
	$class->new($folder, 'HASH');
}

#--------------------
=section Attributes
=cut

#--------------------
=section Tied Interface

=method FETCH $message_id
Get the message with the specified id.  The returned message may be
a dummy if message thread detection is used.  Returns undef when
there is no message with the specified id.

=examples
  my $msg = $inbox{$msgid};
  if($inbox{$msgid}->isDummy)  ...
=cut

sub FETCH($) { $_[0]->folder->messageId($_[1]) }

=method STORE undef, $message
Store a message in the folder.  The key must be undef, because the
message-id of the specified message is taken.  This is shown in the
first example.  However, as you see, it is a bit complicated to specify
undef, therefore the string C<"undef"> is accepted as well.

The message may be converted into something which can be stored in the
folder type which is at stake.  The added instance is returned.

=examples

  $inbox{ (undef) } = $msg;
  $inbox{undef} = $msg;

=warning use undef as key, because the message-id of the message is used.
=cut

sub STORE($$)
{	my ($self, $key, $basicmsg) = @_;

	! defined $key || $key eq 'undef'
		or warning __x"use undef as key, because the message-id of the message is used.";

	$self->folder->addMessages($basicmsg);
}

=method FIRSTKEY
See M<NEXTKEY()>.
=cut

sub FIRSTKEY()
{	my $self   = shift;
	$self->{MBT_each_index} = 0;
	$self->NEXTKEY();
}

=method NEXTKEY $previous

M<FIRSTKEY()> returns the first message-id/message pair from the folder,
and NEXTKEY returns the message-id/message pair for the next message,
in the order in which the message is stored in the folder.

Messages flagged for deletion will B<not> be returned. See the
M<Mail::Box::messages()> method of the folder type for more information
about the folder message order.

=examples

  foreach my $msgid (keys %inbox) ...
  foreach my $msg (values %inbox) ...

  while(my ($msgid, $msg) = each %inbox) {
     $msg->print unless $msg->isDeleted;
  }

=cut

sub NEXTKEY($)
{	my $self   = shift;
	my $folder = $self->{MBT_folder};
	my $nrmsgs = $folder->messages;

	my $msg;
	while(1)
	{	my $index = $self->{MBT_each_index}++;
		$index < $nrmsgs or return undef;
		$msg      = $folder->message($index);
		$msg->isDeleted or last;
	}

	$msg->messageId;
}

=method EXISTS $message_id
Check whether a message with a certain $message_id exists.

=example
  if(exists $inbox{$msgid}) ...
=cut

sub EXISTS($)
{	my ($self, $msgid) = @_;
	my $msg = $self->folder->messageId($msgid);
	defined $msg && ! $msg->isDeleted;
}

=method DELETE $message_id
Remove the message with the specified $message_id.

=example
  delete $inbox{$msgid};
=cut

sub DELETE($)
{	my ($self, $msgid) = @_;
	$self->folder->messageId($msgid)->delete;
}

=method CLEAR
Remove the contents of the hash.  This is not really possible, but all
the messages will be flagged for deletion.

=examples
  %inbox = ();
  %inbox = ($msg->messageId, $msg); #before adding msg
=cut

sub CLEAR()
{	my $self = shift;
	$_->delete for $self->folder->messages;
}

1;
