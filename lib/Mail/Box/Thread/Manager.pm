#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Thread::Manager;
use parent 'Mail::Reporter';

use strict;
use warnings;

use Log::Report             'mail-box';

use Mail::Box::Thread::Node ();
use Mail::Message::Dummy    ();
use Scalar::Util            qw/blessed/;

#--------------------
=chapter NAME

Mail::Box::Thread::Manager - maintain threads within a set of folders

=chapter SYNOPSIS

  my $mgr     = Mail::Box::Manager->new;
  my $folder  = $mgr->open(folder => '/tmp/inbox');

  my $threads = $mgr->threads();
  $threads->includeFolder($folder);

  my $threads = $msg->threads(folder => $folder);

  foreach my $thread ($threads->all) {
      $thread->print;
  }

  $threads->removeFolder($folder);

=chapter DESCRIPTION

A (message-)I<thread> is a message with links to messages which followed in
reply of that message.  And then the messages with replied to the messages,
which replied the original message.  And so on.  Some threads are only
one message long (never replied to), some threads are very long.

The C<Mail::Box::Thread::Manager> is very powerful.  Not only is it able to
do a descent job on MH-like folders (makes a trade-off between perfection
and speed), it also can maintain threads from messages residing in different
opened folders.  Both facilities are rare for mail-agents.  The manager
creates flexible trees with Mail::Box::Thread::Node objects.

=chapter METHODS

=c_method new %options
A thread manager object is usually created by a Mail::Box::Manager.
One manager can produce more than one of these objects.  One thread
manager can combine messages from a set of folders, which may be partially
overlapping with other objects of the same type.

=option  dummy_type CLASS
=default dummy_type Mail::Message::Dummy
The type of dummy messages.  Dummy messages are used to fill holes in
detected threads: referred to by messages found in the folder, but itself
not in the folder.

=option  folder $folder|\@folders
=default folder C<[ ]>
Specifies which @folders are to be covered by the threads.  You can
specify one or more open folders.  When you close a folder, the
manager will automatically remove the messages of that folder from
your threads.

=option  folders $folder|\@folders
=default folders C<[ ]>
Equivalent to the P<folder> option.

=option  thread_type CLASS
=default thread_type Mail::Box::Thread::Node
Type of the thread nodes.

=option  window INTEGER|'ALL'
=default window C<10>
The thread-window describes how many messages should be checked at
maximum to fill `holes' in threads for folder which use delay-loading
of message headers.

The constant 'ALL' will cause thread-detection not to stop trying
to fill holes, but continue looking until the first message of the folder
is reached.  Gives the best quality results, but may perform bad.

=option  timespan TIME | 'EVER'
=default timespan C<'3 days'>
Specify how fast threads usually work: the amount of time between an
answer and a reply.  This is used in combination with the P<window>
option to determine when to give-up filling the holes in threads.

See Mail::Box::timespan2seconds() for the possibilities for TIME.
With 'EVER', the search for messages in a thread
will only be limited by the window-size.

=option  thread_body BOOLEAN
=default thread_body false
May thread-detection be based on the content of a message?  This has
a serious performance implication when there are many messages without
C<In-Reply-To> and C<References> headers in the folder, because it
will cause many messages to be parsed. NOT IMPLEMENTED YET.

=examples

  use Mail::Box::Manager;
  my $mgr     = Mail::Box::Manager->new;
  my $inbox   = $mgr->open(folder => $ENV{MAIL});
  my $read    = $mgr->open(folder => 'Mail/read');
  my $threads = $mgr->threads(folders => [$inbox, $read]);

  # longer alternative for last line:
  my $threads = $mgr->threads;
  $threads->includeFolder($inbox);
  $threads->includeFolder($read);

=error thread manager needs a folder manager to work with.
=cut

sub init($)
{	my ($self, $args) = @_;
	$self->{MBTM_manager} = $args->{manager}
		or error __x"thread manager needs a folder manager to work with.";

	$self->{MBTM_thread_body}= $args->{thread_body} // 0;
	$self->{MBTM_thread_type}= $args->{thread_type} // 'Mail::Box::Thread::Node';
	$self->{MBTM_dummy_type} = $args->{dummy_type}  // 'Mail::Message::Dummy';
	$self->{MBTM_window}     = $args->{window}      // 10;
	$self->{MBTM_ids}        = +{ };
	$_[0]->{MBTM_folders}    = +{ };

	my $ts = $args->{timespan} || '3 days';
	$self->{MBTM_timespan} = $ts eq 'EVER' ? 'EVER' : Mail::Box->timespan2seconds($ts);
	$self;
}

#--------------------
=section Attributes

=method folderIndex
=method folders
Returns the folders as managed by this threader.
=method folder $name
=cut

sub folderIndex() { $_[0]->{MBTM_folders} }
sub folders()     { values %{$_[0]->folderIndex} }
sub folder($)     { $_[0]->folderIndex->{$_[1]} }

=method byId
Returns a reference to the index which maps message ids to messages.
=cut

sub byId { $_[0]->{MBTM_ids} }

=method msgById $id, [$node]
Returns the message which the specified $id.
=cut

sub msgById($) { my $ids = $_[0]->byId; @_ > 2 ? $ids->{$_[1]} = $_[2] : $ids->{$_[1]} }

#--------------------
=section Grouping Folders

=method includeFolder @folders
Add one or more @folders to the LIST of folders whose messages are
organized in the threads maintained by this object.  Duplicated
inclusions will not cause any problems.

From the folders, the messages which have their header lines parsed
(see Mail::Box about lazy extracting) will be immediately scanned.
Messages of which the header is known only later will have to report this
(see M<toBeThreaded()>).

=example
  $threads->includeFolder($inbox, $draft);

=error attempt to include a none folder: '$something'.
=cut

sub includeFolder(@)
{	my $self  = shift;
	my $index = $self->folderIndex;

	foreach my $folder (@_)
	{	blessed $folder && $folder->isa('Mail::Box')
			or error __x"attempt to include a none folder: '{something EL(20)}'.", something => blessed $folder // $folder;

		my $name = $folder->name;
		next if exists $index->{$name};

		$index->{$name} = $folder;
		$self->inThread($_) for grep ! $_->head->isDelayed, $folder->messages;
	}

	$self;
}

=method removeFolder @folders
Remove one or more @folders from the LIST of folders whose messages are
organized in the threads maintained by this object.

=example
  $threads->removeFolder($draft);

=error attempt to remove a none folder: '{something}'.
=cut

sub removeFolder(@)
{	my $self  = shift;
	my $index = $self->folderIndex;

	foreach my $folder (@_)
	{	blessed $folder && $folder->isa('Mail::Box')
			or error __x"attempt to remove a none folder: '{something EL(20)}'.", something => blessed $folder // $folder;

		my $name = $folder->name;
		delete $index->{$name} or next;

		$_->headIsRead && $self->outThread($_)
			for $folder->messages;

		$self->{MBTM_cleanup_needed} = 1;
	}

	$self;
}

#--------------------
=section The Threads

=method thread $message
Returns the thread where this $message is the start of.  However, there
is a possibility that this message is a reply itself.

Usually, all messages which are in reply of this message are dated later
than the specified one.  All headers of messages later than this one are
getting parsed first, for each folder in this threads-object.

=examples

  my $threads = $mgr->threads(folder => $inbox);
  my $thread  = $threads->thread($inbox->message(3));
  print $thread->string;

=cut

sub thread($)
{	my ($self, $message) = @_;
	my $msgid     = $message->messageId;
	my $timestamp = $message->timestamp;

	$self->_processDelayedNodes;
	my $thread    = $self->msgById($msgid) or return;

	my @missing;
	$thread->recurse( sub {
		my $node = shift;
		push @missing, $node->messageId if $node->isDummy;
		1;
	});

	@missing or return $thread;

	foreach my $folder ($self->folders)
	{
		# Pull-in all messages received after this-one, from any folder.
		# Clocks may drift a bit, so use margin.
		my @now_missing = $folder->scanForMessages($msgid, \@missing, $timestamp - 3600, 0);

		if(@now_missing != @missing)
		{	$self->_processDelayedNodes;
			@now_missing or last;
			@missing = @now_missing;
		}
	}

	$thread;
}

=method threadStart $message
Based on a $message, and facts from previously detected threads, try
to build solid knowledge about the thread where this message is in.
=cut

sub threadStart($)
{	my ($self, $message) = @_;
	my $thread = $self->thread($message) or return;

	while(my $parent = $thread->repliedTo)
	{	unless($parent->isDummy)
		{	# Message already found, no special action to be taken.
			$thread = $parent;
			next;
		}

		foreach my $folder ($self->folders)
		{	my $message  = $thread->message;
			my $timespan = $message->isDummy ? 'ALL' : $message->timestamp - $self->{MBTM_timespan};

			$folder->scanForMessages($thread->messageId, $parent->messageId, $timespan, $self->{MBTM_window})
				or last;
		}

		$self->_processDelayedNodes;
		$thread = $parent;
	}

	$thread;
}

=method all
Returns all messages which start a thread.  The list may contain dummy
messages and messages which are scheduled for deletion.

To be able to return all threads, thread construction on each
message is performed first, which may be slow for some folder-types
because is will enforce parsing of message-bodies.
=cut

sub all()
{	my $self = shift;
	$_->find('not-existing') for $self->folders;
	$self->known;
}

=method sortedAll [$prepare, [$compare]]
Returns M<all()> the threads by default, but sorted on timestamp.
=cut

sub sortedAll(@)
{	my $self = shift;
	$_->find('not-existing') for $self->folders;
	$self->sortedKnown(@_);
}

=method known
Returns the list of all messages which are known to be the start of
a thread.  Threads containing messages which where not read from their
folder (like often happens MH-folder messages) are not yet known, and
hence will not be returned.

The list may contain dummy messages, and messages which are scheduled
for deletion.  Threads are detected based on explicitly calling
M<inThread()> and M<thread()> with a messages from the folder.

Be warned that, each time a message's header is read from the folder,
the return of the method can change.
=cut

sub known()
{	my $self      = shift->_processDelayedNodes->_cleanup;
	grep !defined $_->repliedTo, values %{$self->byId};
}

=method sortedKnown [$prepare, [$compare]]
Returns all M<known()> threads, in sorted order.  By default, the threads
will be sorted on timestamp, But a different $compare method can be
specified.
=cut

sub sortedKnown(;$$)
{	my $self    = shift;
	my $prepare = shift || sub { $_[0]->startTimeEstimate || 0 };
	my $compare = shift || sub { $_[0] <=> $_[1] };

	# Special care for double keys.
	my %value;
	push @{$value{$prepare->($_)}}, $_ for $self->known;
	map @{$value{$_}}, sort {$compare->($a, $b)} keys %value;
}

# When a whole folder is removed, many threads can become existing
# only of dummies.  They must be removed.

sub _cleanup()
{	my $self = shift;
	$self->{MBTM_cleanup_needed} or return $self;

	foreach my $thread ($self->known)
	{	my $real = 0;
		$thread->recurse( sub {
			my $node = shift;
			foreach my $msg ($node->messages)
			{	next if $msg->isDummy;
				$real = 1;
				return 0;
			}
			1;
		});

		next if $real;

		$thread->recurse( sub {
			my $node  = shift;
			delete $self->byId->{$node->messageId};
			1;
		});
	}

	delete $self->{MBTM_cleanup_needed};
	$self;
}

#--------------------
=section Internals

=method toBeThreaded $folder, @messages
Include the specified messages in/from the threads managed by
this object, if this folder is maintained by this thread-manager.
=cut

sub toBeThreaded($@)
{	my ($self, $folder) = (shift, shift);
	$self->folder($folder->name) or return $self;
	$self->inThread($_) for @_;
	$self;
}

=method toBeUnthreaded $folder, @messages
Remove the specified @messages in/from the threads managed by
this object, if this folder is maintained by this thread-manager.
=cut

sub toBeUnthreaded($@)
{	my ($self, $folder) = (shift, shift);
	$self->folder($folder->name) or return $self;
	$self->outThread($_) for @_;
	$self;
}

=method inThread $message
Collect the thread-information of one message.  The `In-Reply-To' and
`Reference' header-fields are processed.  If this method is called on
a message whose header was not read yet (as usual for MH-folders,
for instance) the reading of that header will be triggered here.
=cut

sub inThread($)
{	my ($self, $message) = @_;
	my $msgid = $message->messageId;
	my $node  = $self->msgById($msgid);

	# Already known, but might reside in many folders.
	if($node) { $node->addMessage($message) }
	else
	{	$node = Mail::Box::Thread::Node->new(message => $message, msgid => $msgid, dummy_type => $self->{MBTM_dummy_type});
		$self->msgById($msgid, $node);
	}

	$self->{MBTM_delayed}{$msgid} = $node; # removes doubles.
}

# The relation between nodes is delayed, to avoid that first
# dummy nodes have to be made, and then immediately upgrades
# to real nodes.  So: at first we inventory what we have, and
# then build thread-lists.

sub _processDelayedNodes()
{	my $self    = shift;
	$self->{MBTM_delayed} or return $self;

	foreach my $node (values %{$self->{MBTM_delayed}})
	{	$self->_processDelayedMessage($node, $_) for $node->message;
	}

	delete $self->{MBTM_delayed};
	$self;
}

sub _processDelayedMessage($$)
{	my ($self, $node, $message) = @_;
	my $msgid = $message->messageId;

	# will force parsing of head when not done yet.
	my $head  = $message->head or return $self;

	my $replies;
	if(my $irt  = $head->get('in-reply-to'))
	{	for($irt =~ m/\<(\S+\@\S+)\>/)
		{	my $msgid = $1;
			$replies  = $self->msgById($msgid) || $self->createDummy($msgid);
		}
	}

	my @refs;
	if(my $refs = $head->get('references'))
	{	while($refs =~ s/\<(\S+\@\S+)\>//s)
		{	my $msgid = $1;
			push @refs, $self->msgById($msgid) || $self->createDummy($msgid);
		}
	}

	# Handle the `In-Reply-To' message header.
	# This is the most secure relationship.

	if($replies)
	{	$node->follows($replies, 'REPLY')
			and $replies->followedBy($node);
	}

	# Handle the `References' message header.
	# The (ordered) list of message-IDs give an impression where this
	# message resides in the thread.  There is a little less certainty
	# that the list is correctly ordered and correctly maintained.

	if(@refs)
	{	push @refs, $node unless $refs[-1] eq $node;
		my $from = shift @refs;

		while(my $to = shift @refs)
		{	$to->follows($from, 'REFERENCE')
				and $from->followedBy($to);
			$from = $to;
		}
	}

	$self;
}

=method outThread $message
Remove the message from the thread-infrastructure.  A message is
replaced by a dummy.
=cut

sub outThread($)
{	my ($self, $message) = @_;
	my $msgid = $message->messageId;
	my $node  = $self->msgById($msgid) or return $message;

	$node->{MBTM_messages} = [ grep $_ ne $message, @{$node->{MBTM_messages}} ];
	$self;
}

=method createDummy $message_id
Get a replacement message to be used in threads.  Be warned that a
dummy is not a member of any folder, so the program working with
threads must test with M<Mail::Message::isDummy()> before trying things only
available to real messages.
=cut

sub createDummy($)
{	my ($self, $msgid) = @_;
	$self->byId->{$msgid} = $self->{MBTM_thread_type}->new(msgid => $msgid, dummy_type => $self->{MBTM_dummy_type});
}

#--------------------
=chapter DETAILS

This module implements thread-detection on a folder.  Messages created
by the better mailers will include C<In-Reply-To> and C<References>
lines, which are used to figure out how messages are related.  If you
prefer a better thread detection, they are implementable, but there
may be a serious performance hit (depends on the type of folder used).

=section Maintaining threads

A C<Mail::Box::Thread::Manager> object is created by the
Mail::Box::Manager, using M<Mail::Box::Manager::threads()>.
Each object can monitor the thread-relations between messages in one
or more folders.  When more than one folder is specified, the messages
are merged while reading the threads, although nothing changes in the
folder-structure.  Adding and removing folders which have to be maintained
is permitted at any moment, although may be quite costly in performance.

An example of the maintained structure is shown below.  The
Mail::Box::Manager has two open folders, and a thread-builder which
monitors them both.  The combined folders have two threads, the second
is two long (msg3 is a reply on msg2).  Msg2 is in two folders at once.

  manager
   |    \
   |     `----------- threads
   |                  |     |
   |                thread thread---thread
   |                  |    /|        /
   |                  |   //        /
   +---- folder1      |  //        /
   |       |         /  //        /
   |       `-----msg1  //        /
   |       `-----msg2-'/        /
   |                  /        /
   `-----folder2     /        /
           |        /        /
           `-----msg2       /
           `-----msg3------'

=section Delayed thread detection

With M<all()> you get the start-messages of each thread of this folder.
When that message was not found in the folder (not saved or already
removed), you get a message of the dummy-type.  These thread descriptions
are in perfect state: all messages of the folder are included somewhere,
and each missing message of the threads (I<holes>) are filled by dummies.

However, to be able to detect all threads it is required to have the
headers of all messages, which is very slow for some types of folders,
especially MH and IMAP folders.

For interactive mail-readers, it is preferred to detect threads only
on messages which are in the viewport of the user.  This may be sloppy
in some situations, but everything is preferable over reading an MH
mailbox with 10k e-mails to read only the see most recent messages.

In this object, we take special care not to cause unnecessary parsing
(loading) of messages.  Threads will only be detected on command, and
by default only the message headers are used.

The following reports the Mail::Box::Thread::Node which is
related to a message:

  my $thread = $message->thread;

When the message was not put in a thread yet, it is done now.  But, more
work is done to return the best thread.  Based on various parameters,
which where specified when the folder was created, the method walks
through the folder to fill the holes which are in this thread.

Walking from back to front (recently arrived messages are usually in the back
of the folder), message after message are triggered to be included in their
thread.  At a certain moment, the whole thread of the requested method
is found, a certain maximum number of messages was tried, but that
didn't help (search window bound reached), or the messages within the
folder are getting too old.  Then the search to complete the thread will
end, although more messages of them might have been in the folder: we
don't scan the whole folder for performance reasons.

Finally, for each message where the head is known, for instance for
all messages in mbox-folders, the correct thread is determined
immediately.  Also, all messages where the head get loaded later, are
automatically included.

=cut

1;
