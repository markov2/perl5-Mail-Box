
package Mail::Box::Threads;

use strict;
use 5.006;
our $VERSION = v0.9;

use Mail::Box::Message;

=head1 NAME

Mail::Box::Threads - maintain threads within a folder

=head1 SYNOPSIS

   my Mail::Box $folder = ...;
   foreach my $thread ($folder->threads)
   {   $thread->printThread;
   }

=head1 DESCRIPTION

Read Mail::Box::Manager and Mail::Box first.  The manual also describes
package Mail::Box::Thread, which is one thread.

A (message-)I<thread> is a message, with the messages which followed in
reply on that message.  And the messages with replied the messages
which replied the original message.  And so on.  Some threads are only
one message (never replied to), some threads are very long.

=head2 What can we do?

This module implements thread-detection on a folder.  Messages created
by the better mailers will include C<In-Reply-To> and C<References>
lines, which are used to figure out how messages are related.  If you
prefer a better thread detection, then you can ask for it, but there
may be a serious performance hit (depends on the type of folder used).

=head2 How to use it?

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

=item How is it implemented?

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

=item * thread_window => INTEGER|'ALL'

The thread-window describes how many messages should be checked at
maximum to fill `holes' in threads for folder which use delay-loading
of message headers.  The default value is 10.

The constant 'ALL' will cause thread-detection not to stop trying
to fill holes, but continue looking until the first message of the folder
is reached.  Gives the best quality results, but may perform bad.

=item * thread_timespan => TIME|'EVER'

Specify how fast threads usually work: the amount of time between an
answer and a reply.  This is used in combination with the C<thread_window>
option to determine when to give-up filling the holes in threads.

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:

    thread_timespan => '1 hour'
    thread_timespan => '4 weeks'

The default is '3 days'.  TIME may also be the string 'EVER', which will
effectively remove this limit.

=item * thread_body => BOOL

May thread-detection be based on the content of a message?  This has
a serious performance implication when there are many messages without
C<In-Reply-To> and C<References> headers in the folder, because it
will cause many messages to be parsed.

NOT USED YET.  Defaults to FALSE.

=item
=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->registerHeaders(qw/message-id in-reply-to references/);

    $self->{MBT_dummy_type}      = $args->{dummy_type}
                                || $self->{MB_message_type} . '::Dummy';
    $self->{MBT_thread_body}     = $args->{thread_body}        || 0;

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

=item thread MESSAGE

Based on a message, and facts from previously detected threads, try
to build solid knowledge about the thread where this message is in.

=cut

sub thread($)
{   my ($self, $message) = @_;

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
C<inThread> and C<thread> with a messages from the folder.

Be warned that, each time a message's header is read from the folder,
the return of the method can change.

=cut

sub knownThreads() { values %{shift->{MBT_threads}} }

###
### Mail::Box::Thread
###

package Mail::Box::Thread;

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
{   use Carp;
    confess "Extentions of a thread shall implement the folder() method.";
}

#-------------------------------------------

=item thread

Returns the first message in the thread where this message is part
of.  This may be this message itself.  This also may return any other
message in the folder.  Even a dummy message can be returned, when the
first message in the thread was not stored in the folder.

Example:
    my $start = $folder->message(42)->thread;

=cut

sub thread()
{   my $self = shift;
    $self->folder->thread($self);
}

#-------------------------------------------

=item inThread

Include the message in a thread.  If the message was not known to the
thread-administration yet, it will be added to those structures.

=cut

sub inThread()
{   my $self = shift;
    $self->folder->inThread($self);
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

sub repliedTo()
{   my $self = shift;

    return wantarray
         ? ($self->{MBT_parent}, $self->{MBT_quality})
         : $self->{MBT_parent};
}

#-------------------------------------------

=item follows MESSAGE|MESSAGE-ID, STRING

Register that the specified MESSAGE (or MESSAGE-ID) is a reply on this
message, where the quality of the relation is specified by the constant
STRING.

The relation may be specified more than once, but there can be only one.
Once a reply (STRING equals C<REPLY>) is detected, that value will be
kept.

=cut

sub follows($$)
{   my ($self, $message, $how) = @_;

#print "($self, $message, $how)\n";
    unless(exists $self->{MBT_parent} && $self->{MBT_quality} eq 'REPLY')
    {   $self->{MBT_parent}  = ref $message ? $message->messageID : $message;
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
{   my $self   = shift;
    my $folder = $self->folder;
    map {$folder->messageID($_)} @{$self->{MBT_followUps}};
}

sub followUpIDs() { @{shift->{MBT_followUps}} }

#-------------------------------------------

=item threadFilled [BOOL]

Returns (after setting) a flag whether the thread (where this message
is the start of) is fully processed in finding holes.  If this is set
on TRUE, than any dummies still in this thread could not be found
within the limits of C<thread_window> and C<thread_timespan>.

=cut

sub threadFilled(;$)
{   my $self = shift;
    @_ ? $self->{MBT_full} = shift : $self->{MBT_full};
}

#-------------------------------------------

=back

=head2 Actions on whole threads

Some conveniance methods are added to threads, to simplify retreiving
knowledge from it.

=over 4

=item recurseThread CODE-REF

Execute a function for all sub-threads.  If the subroutine returns true,
sub-threads are visited, too.  Otherwise, this branch is aborted.

=cut

sub recurseThread($)
{   my ($self, $code) = @_;
    $code->($self);
    $_->recurseThread($code) foreach $self->followUps;
    $self;
}

#-------------------------------------------

=item totalSize

Sum the size of all the messages in the thread.

=cut

sub totalSize()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {$total += shift->size; 1} );
    $total;
}

#-------------------------------------------

=item nrMessages

Number of messages in this thread.

=cut

sub nrMessages()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {++$total} );
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

=item folded [BOOL]

Returns whether this (part of the) folder has to be shown folded or not.  This
is simply done by a label, which means that most folder-types can store this.

=cut

sub folded(;$)
{   my $self = shift;
    $self->setLabel(folded => shift) if @_;
    $self->label('folded') || 0;
}

#-------------------------------------------

=item threadToString

Translate a thread into a string.  The string will contain at least one
line for each message which was found, but tries to fold dummies.
This is useful for debugging, but most message-readers
will prefer to implement their own thread printer.

Example:
   print $message->threadToString;

may result in
   Subject of this message
   |- Re: Subject of this message
   |-*- Re: Re: Subject of this message
   | |- Re(2) Subject of this message
   | |- [3] Re(2) Subject of this message
   | `- Re: Subject of this message (reply)
   `- Re: Subject of this message

The `*' represents a lacking message.  The `[3]' presents a folded thread with
three messages.

=cut

sub threadToString(;$$)
{   my ($self, $first, $other) = (shift, shift || '', shift || '');

    my @follows = $self->followUps;

    my @out;

    if($self->folded)
    {   my $subject = $self->head->get('subject');
        chomp $subject if $subject;
        return "    $first [" . $self->nrMessages . '] '. ($subject||'')."\n";
    }
    elsif($self->isDummy)
    {   $first .= $first ? '-*-' : ' *-';
        return (shift @follows)->threadToString($first, "$other   " )
            if @follows==1;

        push @out, (shift @follows)->threadToString($first, "$other | " )
            while @follows > 1;
    }
    else
    {   my $subject = $self->head->get('subject');
        my $size    = $self->shortSize;
        chomp $subject if $subject;
        @out = "$size$first ". ($subject || ''). "\n";
        push @out, (shift @follows)->threadToString( "$other |-", "$other | " )
            while @follows > 1;
    }

    push @out, (shift @follows)->threadToString( "$other `-", "$other   " )
        if @follows;

    join '', @out;
}

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.9

=cut

1;
