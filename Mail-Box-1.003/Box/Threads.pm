
use strict;
package Mail::Box::Threads;

use Mail::Box::Message;
use Mail::Box::Thread;

=head1 NAME

Mail::Box::Threads - maintain threads within a folder

=head1 SYNOPSIS

   my Mail::Box $folder = ...;
   foreach my $thread ($folder->threads)
   {   $thread->printThread;
   }

=head1 DESCRIPTION

Read L<Mail::Box::Manager> and L<Mail::Box> first.  It might be helpfull
to study L<Mail::Box::Thread> too.

A (message-)I<thread> is a message, with the messages which followed in
reply on that message.  And the messages with replied the messages
which replied the original message.  And so on.  Some threads are only
one message (never replied to), some threads are very long.


=head1 METHODS

=over 4

=item new ARGS

C<Mail::Box::Threads> is sub-classed always by C<Mail::Box>.  This object is
not meant to be instantiated itself: do not call C<new> on it (you'll
see it even fails because there is no C<new()>!).

The construction of thread administration accepts the following options:

=over 4

=item * dummy_type =E<gt> CLASS

Of which class are dummy messages?  Usually, this is the basic
dummy type, L<Mail::Box::Message::Dummy>, unless you intend to
extend the object.

=item * thread_window =E<gt> INTEGER|'ALL'

The thread-window describes how many messages should be checked at
maximum to fill `holes' in threads for folder which use delay-loading
of message headers.  The default value is 10.

The constant 'ALL' will cause thread-detection not to stop trying
to fill holes, but continue looking until the first message of the folder
is reached.  Gives the best quality results, but may perform bad.

=item * thread_timespan =E<gt> TIME|'EVER'

Specify how fast threads usually work: the amount of time between an
answer and a reply.  This is used in combination with the C<thread_window>
option to determine when to give-up filling the holes in threads.

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:

    thread_timespan => '1 hour'
    thread_timespan => '4 weeks'

The default is '3 days'.  TIME may also be the string 'EVER', which will
effectively remove this limit.

=item * thread_body =E<gt> BOOL

May thread-detection be based on the content of a message?  This has
a serious performance implication when there are many messages without
C<In-Reply-To> and C<References> headers in the folder, because it
will cause many messages to be parsed.

NOT USED YET.  Defaults to FALSE.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->registerHeaders(qw/message-id in-reply-to references/);

    $self->{MBT_dummy_type}  = $args->{dummy_type}
                               || 'Mail::Box::Message::Dummy';
    $self->{MBT_thread_body} = $args->{thread_body} || 0;

    for($args->{thread_timespan} || '3 days')
    {   $self->{MBT_timespan}
            = $_ eq 'EVER' ? $_ : $self->timespan2seconds($_);
    }

    for($args->{thread_window} || 10)
    {   $self->{MBT_window} = $_ eq 'ALL'  ? -1 : $_;
    }

    $self;
}

sub timespan2seconds($)
{   
    if( $_[1] =~ /^\s*(\d+\.?\d*|\.\d+)\s*(hour|day|week)s?\s*$/ )
    {     $2 eq 'hour' ? $1 * 3600
        : $2 eq 'day'  ? $1 * 86400
        :                $1 * 604800;  # week
    }
    else
    {   warn "Invalid timespan '$_' specified.\n";
        undef;
    }
}

#-------------------------------------------

=item toBeThreaded MESSAGE [, ...]

=item toBeUnthreaded MESSAGE-ID [, ...]

Register a message to be put in (withdrawn from) a thread when the
user is asking for threads.  If no-one ever asks for threads, then
no work is done on them.

=cut

sub toBeThreaded(@)
{   my $self = shift;
    push @{$self->{MBT_to_be_threaded}}, @_;
    $self;
}

sub toBeUnthreaded(@)
{   my $self = shift;
    push @{$self->{MBT_to_be_unthreaded}}, @_;
    $self;
}


#################
################# AUTOLOAD (when implemented)
#################

#-------------------------------------------

=item createDummy MESSAGE-ID

Create a dummy message for this folder.  The dummy is a place-holder
in a thread description to represent a message which is not found in
the folder (yet).

=cut

sub createDummy($)
{   my ($self, $msgid) = @_;
    my $dummy = $self->{MBT_dummy_type}->new($msgid);
    $dummy->folder($self);
    $self->{MB_dummies}{$msgid} = $dummy;
    $self->messageID($msgid, $dummy);
}

#-------------------------------------------

=item processDelayedThreading

Parse all messages which where detected in the folder, but were not
processed into a thread yet.

=cut

sub processDelayedThreading()
{   my $self = shift;

    if(my $add = $self->{MBT_to_be_threaded})
    {   $self->inThread($_) foreach @$add;
        delete $self->{MBT_to_be_threaded};
    }

    if(my $del = $self->{MBT_to_be_unthreaded})
    {   $self->outThread($_) foreach @$del;
        delete $self->{MBT_to_be_unthreaded};
    }

    $self;
}

#-------------------------------------------

=item thread MESSAGE

Based on a message, and facts from previously detected threads, try
to build solid knowledge about the thread where this message is in.

=cut

sub thread($)
{   my ($self, $message) = @_;

    $self->inThread($message);
    $self->processDelayedThreading;

    # Search for the top of this message's thread.
    my $top = $message;
    while(my $parent = $top->repliedTo)
    {   $top = $self->messageID($parent);
    }

    # Ready when whole folder has been processed.
    return $top if exists $self->{MBT_last_parsed}
                && $self->{MBT_last_parsed} == 0;

    # Inventory on all missing messages in this thread.
    return $top if $top->threadFilled;             # fast bail-out.

    my %missing;
    $top->recurseThread
    ( sub { my $message = shift;
            return 0 if $message->threadFilled;    # don't visit kids
            $missing{$message->messageID}++ if $message->isDummy;
            $message->threadFilled(1);
            1;
          }
    );
    return $top unless keys %missing;              # slow bail-out.

    # Go back through the messages from the folder for max thread_window
    # messages before this one.

    my $start    = ($self->{MBT_last_parsed} || $self->allMessages) -1;
    my $end      = $self->{MBT_window} eq 'ALL' ? 0
                 : $message->seqnr - $self->{MBT_window};
    my $earliest = $self->{MBT_timespan} eq 'EVER' ? 0
                 : $message->timestamp - $self->{MBT_timespan};

    for(my $msgnr = $start; $msgnr >= $end; $msgnr--)
    {   my $add  = $self->message($msgnr);

        unless($add->headIsRead)                 # pull next message in.
        {   $self->inThread($add);
            delete $missing{$add->messageID};
            last unless keys %missing;
        }

        last if $earliest && $add->timestamp < $earliest;
    }

    $top;
}


#-------------------------------------------

=item inThread MESSAGE

Collect the thread-information of one message.  The `In-Reply-To' and
`Reference' header-fields are processed.  If this method is called on
a message whose header was not read yet (as usual for MH-folders,
for instance) the reading of that header will be triggered here.

Examples:

   $folder->inThread($message);
   $message->inThread;    #same

=cut

sub inThread($)
{   my ($self, $message) = @_;

    # First register this message to become part of the threads.
    # Maybe, this message-id has been seen before, and a dummy is
    # place-holding.  Copy the information from the dummy into
    # this message.
    
    my $msgid   = $message->messageID;
    my $head    = $message->head;

    my $replies;
    if(my $irt  = $head->get('in-reply-to'))
    {   $replies = ($irt =~ m/\<(.*?)\>/)[0];
        $replies =~ s/\s+//g;
    }

    my @refs;
    if(my $refs = $head->get('references'))
    {   while( $refs =~ m/<.*?>/g )
        {   (my $msgid = $&) =~ s/\s+//g;
            push @refs, $msgid;
        }
    }

    # If a dummy was holding information for this message-id, we have
    # to take the information stored in it.

    if(my $dummy = $self->{MB_dummies}{$msgid})
    {   $message->followedBy($dummy->followUpIDs);
        $message->follows($dummy->repliedTo);
        delete $self->{MB_dummies}{$msgid};
    }

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
            delete $self->{MBT_threads}{$child}; # not a start
            $from->followedBy($child);
            ($start, $from) = ($child, $to);
        }
    }

    # This message might be a thread-start, when no threading
    # information was found.

    $self->registerThread($message)
        unless $replies || @refs;

    $self;
}

#-------------------------------------------

=item outThread MESSAGE-ID

Remove the message, which is represented by its message-id, from the
thread-infrastructure.  A message is replaced by a dummy, if it has
follow-ups.

=cut

sub outThread($)
{   my ($self, $msgid) = @_;
    $self;
}

#-------------------------------------------

=item registerThread MESSAGE|MESSAGE-ID

Register the message as start of a thread.

=cut

sub registerThread($)
{   my ($self, $message) = @_;
    return $self if $message->repliedTo;
    my $msgid = ref $message ? $message->messageID : $message;
    $self->{MBT_threads}{$msgid} = $message;
    $self;
}

#-------------------------------------------

=item threads

Returns all messages which start a thread.  The list may contain dummy
messages, and messages which are scheduled for deletion.

To be able to return all threads, thread construction on each
message is performed first, which may be slow for some folder-types
because is will enforce parsing of message-bodies.

=cut

sub threads()
{   my $self = shift;
    my $last = ($self->{MBT_last_parsed} || $self->allMessages) - 1;

    if($last > 0)
    {   $self->inThread($_) foreach ($self->allMessages)[0..$last];
        $self->{MBT_last_parsed} = 0;
    }

#warn "TH: ", join("\n", sort keys %{$self->{MBT_threads}}), "\n";
    $self->knownThreads;
}

#-------------------------------------------

=item knownThreads

Returns the list of all messages which are known to be the start of
a thread.  Threads containing messages which where not read from their
folder (like often happends MH-folder messages) are not yet known, and
hence will not be returned.

The list may contain dummy messages, and messages which are scheduled
for deletion.  Threads are detected based on explicitly calling
C<inThread()> and C<thread()> with a messages from the folder.

Be warned that, each time a message's header is read from the folder,
the return of the method can change.

=cut

sub knownThreads() { values %{shift->{MBT_threads}} }

#-------------------------------------------

=back

=head1 IMPLEMENTATION

This module implements thread-detection on a folder.  Messages created
by the better mailers will include C<In-Reply-To> and C<References>
lines, which are used to figure out how messages are related.  If you
prefer a better thread detection, then you can ask for it, but there
may be a serious performance hit (depends on the type of folder used).

=head2 Delayed thread detection

With C<threads> you get the start-messages of each thread of this folder.
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

The user of the folder signals that a message has to be included in
a thread within the thread-list, by calling

   $folder->inThread($message);   #or
   $message->inThread;

This only takes the information from this message, and stores this in
a thread-structure.  You can also directly ask for the thread where
the message is in:

   my $thread = $message->thread;

When the message was not put in a thread, it is done now.  But, more
work is done to return the best thread.  Based on various parameters,
which where specified when the folder was created, the method walks
through the folder to fill the holes which are in this thread.

Walking from back to front (latest messages are usually in the back of
the folder), message after message are triggered to be indexed in their
thread.  At a certain moment, the whole thread of the requested method
is found, a certain maximum number of messages was tried, but that
didn't help (search window bound reached), or the messages within the
folder are getting too old.  Then the search to complete the thread will
end, although more messages of the could be in the folder.

Finally, for each message where the head is known, for instance for
all messages in mbox-folders, the correct thread is determined
immediately.  Also, all messages where the head get loaded later, are
automatically included.

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.003

=cut

1;
