
package Mail::Box::Threads;

use strict;
use v5.6.0;
our $VERSION = v0.6;

use Mail::Box::Message;

=head1 NAME

Mail::Box::Threads - maintain threads within a folder

=head1 SYNOPSIS

   my Mail::Box $folder = ...;
   foreach my $thread ($folder->threads)
   {   $thread->print;
   }

=head1 DESCRIPTION

Read Mail::Box::Manager and Mail::Box first.  The manual also describes
package Mail::Box::Thread, which is one thread.

A (message-)I<thread> is a message, with the messages which followed in
reply on that message.  And the messages with replied the messages
which replied the original message.  And so on.  Some threads are only
one message (never replied to), some threads are very long.

=head2 How it works

This module implements thread-detection on a folder.  Messages created
by the better mailers will include C<In-Reply-To> and C<References>
lines, which are used to figure out how messages are related.  If you
prefer a better thread detection, then you can ask for it, but there
may be a serious performance hit (depends on the type of folder used).

In this object, we take special care not to cause unnessesary parsing
(loading) of messages.  Threads will only be detected on command, and
by default only the message headers are used.

=head2 How to use it

With C<allThreads> you get the start-messages of each detected threads.
When that message was not found in the folder (not saved or already
removed), you get a message of the dummy-type.  These thread descriptions
are in perfect state: all messages are included somewhere.

However, to be able to detect all threads it is required to have the
headers of all messages, which is very slow for some types of folders.
For interactive mail-readers, it is prefered to detect threads only
on messages which are in the viewport of the user.  This may be sloppy
in some situations, but everything is preferable over reading an MH
mailbox with 10k e-mails to read only the most recent messages.

=head1 PUBLIC INTERFACE

=over 4

=item new ARGS

Mail::Box::Threads is sub-classed by Mail::Box itself.  This object is
not meant to be instantiated itself: do not call C<new> on it (you'll
see it even fails because there is no C<new()>!).

The construction of thread administration accepts the following options:

=over 4

=item * dummy_type => CLASS

Of which class are dummy messages?  Usually, this needs to be the
C<message_type> of the folder prepended with C<::Dummy>.  This will also
be the default.

=item * thread_body => BOOL

May thread-detection be based on the content of a message?  This has
a serious performance implication when there are many messages without
C<In-Reply-To> and C<References> headers in the folder, because it
will cause many messages to be parsed.

NOT USED YET.  Defaults to TRUE.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->registerHeaders(qw/message-id in-reply-to references/);

    $self->{MBT_dummy_type}  = $args->{dummy_type}
                            || $self->{MB_message_type} . '::Dummy';
    $self->{MBT_thread_body} = $args->{thread_body} || 1;

    $self;
}

#-------------------------------------------

=item createDummy MESSAGE-ID

Create a dummy message for this folder.  The dummy is a place-holder
in a thread description to represent a message which is not found in
the folder (yet).

=cut

sub createDummy($)
{   my ($self, $msgid) = @_;
    my $dummy = $self->{MBT_dummy_type}->new($msgid);
    $self->messageID($msgid, $dummy);
}

#-------------------------------------------

=item detectThread MESSAGE

Based on a message, and facts from previously detected threads, try
to build solid knowledge about the thread where this message is in.

=cut

sub detectThread($)
{   my ($self, $message) = @_;

    # First register this message to become part of the threads.
    # Maybe, this message-id has been seen before, and a dummy is
    # place-holding.  Copy the information from the dummy into
    # this message.
    
    my $msgid   = $message->messageID;
    my $replies = $message->in_reply_to;
    my @refs    = $message->references;


    # If a dummy was holding information for this message-id, we have
    # to take the information stored in it.

    my $dummy = $self->messageID($msgid);
    if($dummy && $dummy->isa($self->{MBT_dummy_type}))
    {   $message->followedBy($dummy->followUps);
        $message->follows($dummy->repliedTo);
    }
    $self->messageID($msgid, $message);


    # This message might be a thread-start, when no threading
    # information was found.

    $self->registerThread($message)
        unless $replies || @refs;


    # Handle the `In-Reply-To' message header.
    # This is the most secure relationship.

    if($replies)
    {   $message->follows($replies, 'REPLY');
        delete $self->{MBT_threads}{$msgid};  # am reply, so not a start.
        my $from  = $self->messageID($replies) || $self->createDummy($replies);
        $from->followedBy($msgid);
    }


    # Handle the `References' message header.
    # The (ordered) list of message-IDs give an impression where this
    # message resides in the thread.  There is a little less certainty
    # that the list is correctly ordered and correctly maintained.

    if(@refs)
    {   push @refs, $msgid;
        my $start = shift @refs;
        my $from  = $self->messageID($start) || $self->createDummy($start);
        $self->registerThread($from);

        while(my $child = shift @refs)
        {   my $to = $self->messageID($child) || $self->createDummy($child);
            $to->follows($start, 'REFERENCE');
            delete $self->{MBT_threads}{$child};
            $from->followedBy($child);
            ($start, $from) = ($child, $to);
        }
    }

    $self;
}

#-------------------------------------------

=item registerThread MESSAGE|MESSAGE-ID

Register the message as start of a thread.

=cut

sub registerThread($)
{   my ($self, $message) = @_;
    return $self if $self->repliedTo;
    my $msgid = ref $message ? $message->messageID : $message;
    $self->{MBT_threads}{$msgid} = $message;
    $self;
}

#-------------------------------------------

=item allThreads

Returns all messages which start a thread.  The list may contain dummy
messages, and messages which are scheduled for deletion.

To be able to return all threads, thread construction on each
message is performed first, which may be slow for some folder-types
because is will enforce parsing of message-bodies.

=cut

sub allTheads()
{   my $self = shift;
    $_->detectThread foreach $self->allMessages;
    $self->knownThreads;
}

#-------------------------------------------

=item knownThreads

Return the list of all messages which are known to be the start of
a thread.  Threads are detected based on explicitly calling
C<detectThread> with a messages from the folder.

=cut

sub knownThreads() { keys %{shift->{MBT_threads}} }

###
### Mail::Box::Thread
###

package Mail::Box::Thread;
use Carp;

#-------------------------------------------

=back

=head1 Mail::Box::Thread

A thread implements a list of messages which are related.  The main
object described in the manual-page is the thread-manager, which is
part of a Mail::Box.  The Mail::Box::Thread is sub-classed by a
Mail::Box::Message; each message is part of a thread.

=over 4

=item new ARGS

The instatiation of a thread is done by its subclasses.  You will not
call this method by yourself (it is even not implemented).

In the current implementation, there are no options added to the
Mail::Box::Message's object creation.

=cut

sub init($)
{   my $self = shift;
    $self->{MBT_followups} = [];
    $self;
}

sub folder()
{   confess "Extentions of a thread shall implement the folder() method.";
}

#-------------------------------------------

=item myThread

Returns the first message in the thread where this message is part
of.  This may be this message itself.  This also may return any other
message in the folder.  Even a dummy message can be returned, when the
first message in the thread was not stored in the folder.

Example:
    my $start = $folder->message(42)->myThread;

=cut

sub myThread()
{   my $self = shift;
    exists $self->{MBT_parent} ? $self->{MBT_parent}->myThread : $self;
}

#-------------------------------------------

=item repliedTo

Returns the message where this one is a reply to.  In SCALAR context, this
will return the MESSAGE which was replied to by this one.  This message
object may be a dummy message. In case the message seems to be the
first message of a thread, the value C<undef> is returned. 

In LIST context, this method also returns how sure these are messages
are related.  When extended thread discovery in enabled, then some
magic is applied to relate messages.  In LIST context, the first
returned argment is a MESSAGE, and the second a STRING constant.
Values for the STRING may be:

=over 4

=item * REPLY

This relation was directly derived from an `in-reply-to' message header
field.  The relation is very sure.

=item * REFERENCE

This relation is based on information found in a `Reference' message
header field.  One message may reference a list of messages which
precede it in the thread.  Let's hope they are stored in the right
order.

=item * GUESS

The relation is a big guess, of undetermined type.

=back

More constants may be added later.

Examples:
   my $question = $answer->repliedTo;
   my ($question, $quality) = $answer->repliedTo;
   if($question && $quality eq 'REPLY') { ... };

=cut

sub repliedTo
{   my $self = shift;

    $self->detectThread
        unless exists $self->{MBT_parent};

    return wantarray
         ? ($self->{MBT_parent}, $self->{MBT_quality})
         : $self->{MBT_parent};
}

#-------------------------------------------

=item follows MESSAGE, STRING

Register that the specified MESSAGE is a reply on this message, where
the quality of the relation is specified by the constant STRING.  The
relation may be specified more than once, but there can be only one.
Once a reply (STRING equals C<REPLY>) is detected, that value will be
kept.

=cut

sub follows($$)
{   my ($self, $message, $how) = @_;

    unless(exists $self->{MBT_parent} && $self->{MBT_quality} eq 'REPLY')
    {   $self->{MBT_parent}  = $message->messageID;
        $self->{MBT_quality} = $how;
    }
    $self;
}

#-------------------------------------------

=item followedBy [MESSAGE-ID|MESSAGE, ...]

Register that the MESSAGEs (or MESSAGE-IDs) are follow-ups to this message.
There may be more than one of these follow-ups which are not related to
each-other in any other way than sharing the same parent.

If the same relation is defined more than ones, this will not cause
duplication of information.

=cut

sub followedBy(@)
{   my $self  = shift;

    return $self unless @_;
    unless(exists $self->{MBT_followUps})
    {   $self->{MBT_followUps} = [ map {ref $_ ? $_->messageID : $_} @_ ];
        return $self;
    }

    foreach my $follow (@_)
    {   my $followid = ref $follow ? $follow->messageID : $follow;
        push @{$self->{MBT_followUps}}, $followid
           unless grep {$followid eq $_} @{$self->{MBT_followUps}};
    }

    $self;
}

#-------------------------------------------

=item followUps

Returns the list of follow-ups to this message.  This list
contains parsed, not-parsed, and dummy messages.  C<followUps>
returns MESSAGE-objects, while C<followUpIDs> returns the IDs
only.

=cut

sub followUps()
{   my $self = shift;
    map {$self->{msgid}{$_}} @{$self->{MBT_followUps}};
}

sub followUpIDs() { @{shift->{MBT_followUps}} }

#-------------------------------------------

=back

=head2 Actions on whole threads

Some conveniance methods are added to threads, to simplify retreiving
knowledge from it.

=over 4

=item recurseThread CODE-REF

Execute a function for all sub-threads.

=cut

sub recurseThread($)
{   my ($self, $code) = @_;
    $_->recurseThread($code) foreach $self->subThreads;
    $code->($self);
    $self;
}

#-------------------------------------------

=item totalSize

Sum the size of all the messages in the thread.

=cut

sub totalSize()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {$total += shift->size} );
    $total;
}

#-------------------------------------------

=item nrMessages

Number of messages in this thread.

=cut

sub nrMessages()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {$total++} );
    $total;
}

#-------------------------------------------

=item ids

Collect all the ids in this thread.

Examples:
    $newfolder->addMessages($folder->ids($thread->ids));
    $folder->delete($thread->ids);

=cut

sub ids()
{   my $self = shift;
    my @ids;
    $self->recurseThread( sub {push @ids, shift->messageID} );
    @ids;
}

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.6

=cut

1;
