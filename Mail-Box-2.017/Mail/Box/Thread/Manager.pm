
use strict;
package Mail::Box::Thread::Manager;

use Carp;
use Mail::Box::Message::Dummy;
use Mail::Box::Thread::Node;

=head1 NAME

Mail::Box::Thread::Manager - maintain threads within a set of folders

=head1 SYNOPSIS

 my $mgr     = Mail::Box::Thread::Manager->new;
 my $folder  = $mgr->open(folder => '/tmp/inbox');
 my $threads = $mgr->threads(folder => $folder);
 my $threads = $mgr->threads($folder);   # same

 foreach my $thread ($threads->all)
 {   $thread->print;
 }

 $threads->includeFolder($folder);
 $threads->removeFolder($folder);

=head1 DESCRIPTION

Read C<Mail::Box-Overview> first.  You need to understand the
C<Mail::Box::Thread::Node> too.

A (message-)I<thread> is a message with links to messages which followed in
reply of that message.  And then the messages with replied to the messages,
which replied the original message.  And so on.  Some threads are only
one message long (never replied to), some threads are very long.

The C<Mail::Box::Thread::Manager> is very powerful.  Not only is it able to
do a descent job on MH-like folders (makes a trade-off between perfection
and speed), it also can maintain threads from messages residing in different
opened folders.  Both facilities are rare for mail-agents.

More details about the IMPLEMENTATION at the bottom of this man-page.
BE WARNED: not all possibilities are tested in great detail.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Thread::Manager> objects:

      all                                  removeFolder FOLDERS
      folders                              sortedAll [PREPARE [COMPARE]]
      includeFolder FOLDERS                sortedKnown [PREPARE [,COMP...
      known                                thread MESSAGE
      new ARGS                             threadStart MESSAGE

=head1 METHODS

=over 4

=item new ARGS

A C<Mail::Box::Thread::Manager>-object is created by a C<Mail::Box::Manager>.
One manager can produce more than one of these objects.  One thread-manager can
combine messages from a set of folders, which may be partially overlapping
with other objects of the same type.

The construction of thread administration accepts the following options:

=over 4

=item * dummy_type =E<gt> CLASS

The type of dummy messages.  Dummy messages are used to fill holes in
detected threads: refered to by messages found in the folder, but itselves
not in the folder.  Defaults to L<Mail::Box::Message::Dummy>.

=item * folder =E<gt> FOLDER | REF-ARRAY-FOLDERS

=item * folders =E<gt> FOLDER | REF-ARRAY-FOLDERS

Specifies which folders are to be covered by the threads.  You can
specify one or more open folders.  When you close a folder, the
manager will automatically remove the messages of that folder from
your threads.

=item * thread_type =E<gt> CLASS

Type of the threads, by default C<Mail::Box::Thread::Node>

=item * threader_type =E<gt> CLASS | OBJECT

You can specify a module name (CLASS) or a prepared OBJECT, which can handle
the basic actions required to detect threads.  In both case, the class must be
derived from C<Mail::Box::Thread::Manager>.

=item * window =E<gt> INTEGER|'ALL'

The thread-window describes how many messages should be checked at
maximum to fill `holes' in threads for folder which use delay-loading
of message headers.  The default value is 10.

The constant 'ALL' will cause thread-detection not to stop trying
to fill holes, but continue looking until the first message of the folder
is reached.  Gives the best quality results, but may perform bad.

=item * timespan =E<gt> TIME | 'EVER'

Specify how fast threads usually work: the amount of time between an
answer and a reply.  This is used in combination with the C<window>
option to determine when to give-up filling the holes in threads.

See C<Mail::Box::timespan2seconds> for the possibilities for TIME.
The default is '3 days'.  With 'EVER', the search for messages in a thread
will only be limited by the window-size.

=item * thread_body =E<gt> BOOL

May thread-detection be based on the content of a message?  This has
a serious performance implication when there are many messages without
C<In-Reply-To> and C<References> headers in the folder, because it
will cause many messages to be parsed.

NOT USED YET.  Defaults to FALSE.

=back

Example:

    use Mail::Box::Manager;
    my $mgr     = new Mail::Box::Manager;
    my $inbox   = $mgr->open(folder => $ENV{MAIL});
    my $read    = $mgr->open(folder => 'Mail/read');
    my $threads = $mgr->threads(folders => [$inbox, $read]);

    # longer alternative for last line:
    my $threads = $mgr->threads;
    $threads->includeFolder($inbox);
    $threads->includeFolder($read);

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->{MBTM_manager} = $args->{manager}
        or croak "Need a manager to work with.";

    $self->{MBTM_thread_body}= $args->{thread_body}|| 0;
    $self->{MBTM_dummy_type} = $args->{dummy_type} ||'Mail::Box::Message::Dummy';
    $self->{MBTM_thread_type}= $args->{thread_type}||'Mail::Box::Thread::Node';

    for($args->{timespan} || '3 days')
    {    $self->{MBTM_timespan} = $_ eq 'EVER' ? 'EVER'
                               : Mail::Box->timespan2seconds($_);
    }

    for($args->{window} || 10)
    {   $self->{MBTM_window} = $_ eq 'ALL'  ? 'ALL' : $_;
    }
    $self;
}

#-------------------------------------------

=item folders

Returns the folders as managed by this threader.

=cut

sub folders() { values %{shift->{MBTM_folders}} }

#-------------------------------------------

=item includeFolder FOLDERS

=item removeFolder FOLDERS

Add/Remove a folders to/from the list of folders whose messages are
organized in the threads maintained by this object.  Duplicated
inclusions will not cause any problems.

From the folders, the messages which have their header-lines parsed
(see Mail::Box about lazy extracting) will be immediately scanned.  Messages
of which the header is known only later will have to report this
(see Mail:Box with toBeThreaded).

Example:

    $threads->includeFolder($inbox, $draft);
    $threads->removeFolder($draft);

=cut

sub includeFolder(@)
{   my $self = shift;

    foreach my $folder (@_)
    {   croak "Not a folder: $folder"
            unless ref $folder && $folder->isa('Mail::Box');

        my $name = $folder->name;
        next if exists $self->{MBTM_folders}{$name};

        $self->{MBTM_folders}{$name} = $folder;
        foreach my $msg ($folder->messages)
        {   $self->inThread($msg) unless $msg->head->isDelayed;
        }
    }

    $self;
}

sub removeFolder(@)
{   my $self = shift;

    foreach my $folder (@_)
    {   croak "Not a folder: $folder"
            unless ref $folder && $folder->isa('Mail::Box');

        my $name = $folder->name;
        next unless exists $self->{MBTM_folders}{$name};

        delete $self->{MBTM_folders}{$name};

        $_->headIsRead && $self->outThread($_)
            foreach $folder->messages;

        $self->{MBTM_cleanup_needed} = 1;
    }

    $self;
}

#-------------------------------------------

# toBeThreaded FOLDER, MESSAGES
# toBeUnthreaded FOLDER, MESSAGES
#
# Include/remove the specified messages in/from the threads managed by
# this object, if these folder is maintained by this thread-manager.

sub toBeThreaded($@)
{   my ($self, $folder) = (shift, shift);
    return $self unless exists $self->{MBTM_folders}{$folder->name};
    $self->inThread($_) foreach @_;
    $self;
}

sub toBeUnthreaded($@)
{   my ($self, $folder) = (shift, shift);
    return $self unless exists $self->{MBTM_folders}{$folder->name};
    $self->outThread($_) foreach @_;
    $self;
}

#-------------------------------------------

=item thread MESSAGE

Returns the thread where this MESSAGE is the start of.  However, there
is a possibility that this message is a reply itself.

Usually, all messages which are in reply of this message are dated later
than the specified one.  All headers of messages later than this one are
are getting parsed first, for each folder in this threads-object.

Example:

   my $threads = $mgr->threads(folder => $inbox);
   my $thread  = $threads->thread($inbox->message(3));
   print $thread->toString;

=cut

sub thread($)
{   my ($self, $message) = @_;
    my $msgid     = $message->messageId;
    my $timestamp = $message->timestamp;

    $self->_process_delayed_nodes;
    my $thread    = $self->{MBTM_ids}{$msgid} || return;

    my @missing;
    $thread->recurse
       ( sub { my $node = shift;
               push @missing, $node->messageId if $node->isDummy;
               1;
             }
       );

    return $thread unless @missing;

    foreach my $folder ($self->folders)
    {
        # Pull-in all messages received after this-one, from any folder.
        my @now_missing = $folder->scanForMessages
          ( $msgid
          , [ @missing ]
          , $timestamp - 3600 # some clocks are wrong.
          , 0
          );

        if(@now_missing != @missing)
        {   $self->_process_delayed_nodes;
            last unless @now_missing;
            @missing = @now_missing;
        }
    }

    $thread;
}

#-------------------------------------------

=item threadStart MESSAGE

Based on a message, and facts from previously detected threads, try
to build solid knowledge about the thread where this message is in.

=cut

sub threadStart($)
{   my ($self, $message) = @_;

    my $thread = $self->thread($message) || return;

    while(my $parent = $thread->repliedTo)
    {   unless($parent->isDummy)
        {   # Message already found no special action to be taken.
            $thread = $parent;
            next;
        }

        foreach ($self->folders)
        {   last unless defined $_->scanForMessages
              ( $thread->messageId
              , $parent->messageId
              , $thread->message->timestamp - $self->{MBTM_timespan}
              , $self->{MBTM_window}
              );
        }

        $self->_process_delayed_nodes;
        $thread = $parent;
    }

    $thread;
}


#-------------------------------------------

# inThread MESSAGE
#
# Collect the thread-information of one message.  The `In-Reply-To' and
# `Reference' header-fields are processed.  If this method is called on
# a message whose header was not read yet (as usual for MH-folders,
# for instance) the reading of that header will be triggered here.

sub inThread($)
{   my ($self, $message) = @_;
    my $msgid = $message->messageId;
    my $node  = $self->{MBTM_ids}{$msgid};

    # Already known, but might reside in many folders.
    if($node) { $node->addMessage($message) }
    else
    {   $node = Mail::Box::Thread::Node->new(message => $message
           , msgid => $msgid, dummy_type => $self->{MBTM_dummy_type}
           );
        $self->{MBTM_ids}{$msgid} = $node;
    }
    $self->{MBTM_delayed}{$msgid} = $node; # removes doubles.
}

# The relation between nodes is delayed, to avoid that first
# dummy nodes have to be made, and then immediately upgrades
# to real nodes.  So: at first we inventory what we have, and
# then build threa-lists.

sub _process_delayed_nodes()
{   my $self    = shift;
    return $self unless $self->{MBTM_delayed};

    foreach my $node (values %{$self->{MBTM_delayed}})
    {   $self->_process_delayed_message($node, $_)
            foreach $node->message;
    }

    delete $self->{MBTM_delayed};
    $self;
}

sub _process_delayed_message($$)
{   my ($self, $node, $message) = @_;
    my $msgid = $message->messageId;
    my $head  = $message->head;  # will force parsing of head when not
                         # done yet.

    my $replies;
    if(my $irt  = $head->get('in-reply-to'))
    {   for($irt =~ m/\<([^>]*)\>/)
        {   my $msgid = $1;
            $msgid    =~ s/\s+//g;
            $replies  = $self->{MBTM_ids}{$msgid} || $self->createDummy($msgid);
        }
    }

    my @refs;
    if(my $refs = $head->get('references'))
    {   while($refs =~ s/\<([^>]*)\>//s)
        {   my $msgid = $1;
            $msgid    =~ s/\s//gs;
            push @refs, $self->{MBTM_ids}{$msgid} || $self->createDummy($msgid);
        }
    }

    # Handle the `In-Reply-To' message header.
    # This is the most secure relationship.

    if($replies)
    {   $node->follows($replies, 'REPLY');
        $replies->followedBy($node);
    }

    # Handle the `References' message header.
    # The (ordered) list of message-IDs give an impression where this
    # message resides in the thread.  There is a little less certainty
    # that the list is correctly ordered and correctly maintained.

    if(@refs)
    {   push @refs, $node unless $refs[-1] eq $node;
        my $from = shift @refs;

        while(my $to = shift @refs)
        {   $to->follows($from, 'REFERENCE');
            $from->followedBy($to);
            $from = $to;
        }
    }

    $self;
}

#-------------------------------------------

# outThread MESSAGE
#
# Remove the message from the thread-infrastructure.  A message is
# replaced by a dummy.

sub outThread($)
{   my ($self, $message) = @_;
    my $msgid = $message->messageId;
    my $node  = $self->{MBTM_ids}{$msgid} or return $message;

    $node->{MBTM_messages}
        = [ grep {$_ ne $message} @{$node->{MBTM_messages}} ];

    $self;
}

#-------------------------------------------

# createDummy MESSAGE-ID
#
# Get a replacement message to be used in threads.  Be warned that a
# dummy is not a member of any folder, so the program working with
# threads must test with C<$msg->isDummy> before trying things only
# available to real messages.

sub createDummy($)
{   my ($self, $msgid) = @_;
    $self->{MBTM_ids}{$msgid} = $self->{MBTM_thread_type}->new
            (msgid => $msgid, dummy_type => $self->{MBTM_dummy_type});
}

#-------------------------------------------

=item all

=item sortedAll [PREPARE [COMPARE]]

Returns all messages which start a thread.  The list may contain dummy
messages and messages which are scheduled for deletion.

To be able to return all threads, thread construction on each
message is performed first, which may be slow for some folder-types
because is will enforce parsing of message-bodies.

The C<sortedAll> returns the threads by default sorted on timestamp.

=cut

sub all()
{   my $self = shift;

    $_->scanForMessages(undef, 'not-existing', 'EVER', 'ALL')
        foreach $self->folders;

    $self->known;
}

sub sortedAll(@)
{   my $self = shift;

    $_->scanForMessages(undef, 'not-existing', 'EVER', 'ALL')
        foreach $self->folders;

    $self->sortedKnown(@_);
}

#-------------------------------------------

=item known

=item sortedKnown [PREPARE [,COMPARE]]

Returns the list of all messages which are known to be the start of
a thread.  Threads containing messages which where not read from their
folder (like often happends MH-folder messages) are not yet known, and
hence will not be returned.

The list may contain dummy messages, and messages which are scheduled
for deletion.  Threads are detected based on explicitly calling
C<inThread()> and C<thread()> with a messages from the folder.

Be warned that, each time a message's header is read from the folder,
the return of the method can change.

The C<sortedKnown> returns the threads by default sorted on timestamp.

=cut

sub known()
{   my $self      = shift->_process_delayed_nodes->_cleanup;
    grep {!defined $_->repliedTo} values %{$self->{MBTM_ids}};
}

sub sortedKnown(;$$)
{   my $self    = shift;
    my $prepare = shift || sub {shift->startTimeEstimate||0};
    my $compare = shift || sub {(shift) <=> (shift)};
    Mail::Box->sort($prepare, $compare, $self->known);
}

# When a whole folder is removed, many threads can become existing
# only of dummies.  They must be removed.

sub _cleanup()
{   my $self = shift;
    return $self unless $self->{MBTM_cleanup_needed};

    foreach ($self->known)
    {   my $real = 0;
        $_->recurse
          ( sub { my $node = shift;
                  foreach ($node->messages)
                  {   next if $_->isDummy;
                      $real = 1;
                      return 0;
                  }
                  1;
                }
          );

        next if $real;

        $_->recurse
          ( sub { my $node  = shift;
                  my $msgid = $node->messageId;
                  delete $self->{MBTM_ids}{$msgid};
                  1;
                }
          );
    }

    delete $self->{MBTM_cleanup_needed};
    $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

This module implements thread-detection on a folder.  Messages created
by the better mailers will include C<In-Reply-To> and C<References>
lines, which are used to figure out how messages are related.  If you
prefer a better thread detection, they are implementable, but there
may be a serious performance hit (depends on the type of folder used).

=head2 Maintaining threads

A C<Mail::Box::Thread::Manager>-object is created by the C<Mail::Box::Manager>,
using its C<threads()> method.  Each object can monitor the thread-relations
between messages in one or more folders.  When more than one folder
is specified, the messages are merged while reading the threads, although
nothing changes in the folder-structure.  Adding and removing folders
which have to be maintained is permitted at any moment, although may
be quite costly in performance.

An example of the maintained structure is shown below.  The
C<Mail::Box::Manager> has two open folders, and a thread-builder which
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

=head2 Delayed thread detection

With C<all()> you get the start-messages of each thread of this folder.
When that message was not found in the folder (not saved or already
removed), you get a message of the dummy-type.  These thread descriptions
are in perfect state: all messages of the folder are included somewhere,
and each missing message of the threads (`holes') are filled by dummies.

However, to be able to detect all threads it is required to have the
headers of all messages, which is very slow for some types of folders,
especially MH and IMAP folders.

For interactive mail-readers, it is prefered to detect threads only
on messages which are in the viewport of the user.  This may be sloppy
in some situations, but everything is preferable over reading an MH
mailbox with 10k e-mails to read only the see most recent messages.

In this object, we take special care not to cause unnecessary parsing
(loading) of messages.  Threads will only be detected on command, and
by default only the message headers are used.

The following reports the C<Mail::Box::Thread::Node> object which is
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

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
