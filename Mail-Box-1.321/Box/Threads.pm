
use strict;
package Mail::Box::Threads;

use Carp;

=head1 NAME

Mail::Box::Threads - maintain threads within a set of folders

=head1 SYNOPSIS

   my $mgr     = Mail::Box::Manager->new;
   my $folder  = $mgr->open(folder => '/tmp/inbox');
   my $threads = $mgr->threads(folder => $folder);

   foreach my $thread ($threads->all) {
       $thread->print;
   }

   $threads->includeFolder($folder);
   $threads->removeFolder($folder);

=head1 DESCRIPTION

Read L<Mail::Box::Manager> and L<Mail::Box> first.  This man-page also
describes C<Mail::Box::Thread>.

A (message-)I<thread> is a message with links to messages which followed in
reply of that message.  And then the messages with replied to the messages,
which replied the original message.  And so on.  Some threads are only
one message long (never replied to), some threads are very long.

The Mail::Box::Threads module is very powerful.  Not only is it able to
do a descent job on MH-like folders (makes a trade-off between perfection
and speed), it also can maintain threads from messages residing in different
opened folders.  Both facilities are rare for mail-agents.

More details about the IMPLEMENTATION at the bottom of this man-page.
BE WARNED: not all possibilities are tested in great detail.

=head1 METHODS

=over 4

=item new ARGS

A Mail::Box::Threads-object is created by a Mail::Box::Manager.  One manager
can produce more than one of these objects.  One Mail::Box::Threads-object can
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

Type of the threads, by default Mail::Box::Thread (described lower down
in this manpage).

=item * threader_type =E<gt> CLASS | OBJECT

You can specify a module name (CLASS) or a prepared OBJECT, which can handle
the basic actions required to detect threads.  In both case, the class must be
derived from Mail::Box::Threads.

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

See Mail::Box::timespan2seconds for the possibilities for TIME.
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

    $self->{MBT_manager} = $args->{manager}
        or croak "Need a manager to work with.";

    $self->{MBT_thread_body} = $args->{thread_body} || 0;
    $self->{MBT_dummy_type}  = $args->{dummy_type}  || 'Mail::Box::Message::Dummy';
    $self->{MBT_thread_type} = $args->{dummy_type}  || 'Mail::Box::Thread';

    for($args->{timespan} || '3 days')
    {    $self->{MBT_timespan} = $_ eq 'EVER' ? 'EVER'
                               : Mail::Box->timespan2seconds($_);
    }

    for($args->{window} || 10)
    {   $self->{MBT_window} = $_ eq 'ALL'  ? 'ALL' : $_;
    }
    $self;
}

#-------------------------------------------

=item folders

Returns the folders as managed by this threader.

=cut

sub folders() { values %{shift->{MBT_folders}} }

#-------------------------------------------

=item includeFolder FOLDERS

=item removeFolder FOLDERS

Add/Remove a folders to/from the list of folders whose messages are
organized in the threads maintained by this object.  Duplicated
inclusions will not cause any problems.

From the folders, the messages which have their header-lines parsed
(see Mail::Box about lazy_extract) will be immediately scanned.  Messages
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
        next if exists $self->{MBT_folders}{$name};

        $self->{MBT_folders}{$name} = $folder;
        foreach ($folder->allMessages)
        {   $self->inThread($_) if $_->headIsRead;
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
        next unless exists $self->{MBT_folders}{$name};

        delete $self->{MBT_folders}{$name};
        foreach ($folder->allMessages)
        {   $self->outThread($_) if $_->headIsRead;
        }
        $self->{MBT_cleanup_needed} = 1;
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
    return $self unless exists $self->{MBT_folders}{$folder->name};
    $self->inThread($_) foreach @_;
    $self;
}

sub toBeUnthreaded($@)
{   my ($self, $folder) = (shift, shift);
    return $self unless exists $self->{MBT_folders}{$folder->name};
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
    my $msgid     = $message->messageID;
    my $timestamp = $message->timestamp;

    $self->_processDelayedNodes;
    my $thread    = $self->{MBT_ids}{$msgid} || return;

    my @missing;
    $thread->recurseThread
       ( sub { my $node = shift;
               push @missing, $node->messageID if $node->isDummy;
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
        {   $self->_processDelayedNodes;
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
              ( $thread->messageID
              , $parent->messageID
              , $thread->message->timestamp - $self->{MBT_timespan}
              , $self->{MBT_window}
              );
        }

        $self->_processDelayedNodes;
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
    my $msgid = $message->messageID;
    my $node  = $self->{MBT_ids}{$msgid};

    # Already known, but might reside in many folders.
    if($node) { $node->addMessage($message) }
    else
    {   $node = Mail::Box::Thread->new(message => $message
           , msgid => $msgid, dummy_type => $self->{MBT_dummy_type}
           );
        $self->{MBT_ids}{$msgid} = $node;
    }
    $self->{MBT_delayed}{$msgid} = $node; # removes doubles.
}

# The relation between nodes is delayed, to avoid that first
# dummy nodes have to be made, and then immediately upgrades
# to real nodes.  So: at first we inventory what we have, and
# then build threa-lists.

sub _processDelayedNodes()
{   my $self    = shift;
    return $self unless $self->{MBT_delayed};

    foreach my $node (values %{$self->{MBT_delayed}})
    {   $self->_processDelayedMessage($node, $_)
            foreach $node->message;
    }

    delete $self->{MBT_delayed};
    $self;
}

sub _processDelayedMessage($$)
{   my ($self, $node, $message) = @_;
    my $msgid = $message->messageID;
    my $head  = $message->head;  # will force parsing of head when not
                         # done yet.

    my $replies;
    if(my $irt  = $head->get('in-reply-to'))
    {   for($irt =~ m/(<.*?>)/)
        {   s/\s+//g;
            $replies = $self->{MBT_ids}{$_} || $self->createDummy($_);
        }
    }

    my @refs;
    if(my $refs = $head->get('references'))
    {   foreach ($refs =~ m/<.*?>/g)
        {   s/\s+//g;
            push @refs, $self->{MBT_ids}{$_} || $self->createDummy($_);
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
    my $msgid = $message->messageID;
    my $node  = $self->{MBT_ids}{$msgid} or return $message;

    $node->{MBT_messages}
        = [ grep {$_ ne $message} @{$node->{MBT_messages}} ];

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
    $self->{MBT_ids}{$msgid} = $self->{MBT_thread_type}->new
            (msgid => $msgid, dummy_type => $self->{MBT_dummy_type});
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
{   my $self      = shift->_processDelayedNodes->_cleanup;
    grep {not exists $_->{MBT_parent}} values %{$self->{MBT_ids}};
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
    return $self unless $self->{MBT_cleanup_needed};

    foreach ($self->known)
    {   my $real = 0;
        $_->recurseThread
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

        $_->recurseThread
          ( sub { my $node  = shift;
                  my $msgid = $node->messageID;
                  delete $self->{MBT_ids}{$msgid};
                  1;
                }
          );

        delete $self->{MBT_starts}{$_};
    }

    delete $self->{MBT_cleanup_needed};
    $self;
}

#-------------------------------------------

###
### Mail::Box::Thread
###

package Mail::Box::Thread;
use Carp;
use vars qw/$AUTOLOAD/;

=back

=head1 CLASS Mail::Box::Thread

The Mail::Box::Thread maintains one node in the linked list of threads.
Each node contains one message, and a list of its follow-ups.  Next to
that, the certainty that a message is a follow-up indeed is checked.

=head1 METHODS of Mail::Box::Thread

=cut

#-------------------------------------------

=over 4

=item new OPTIONS

You will not call this method by yourself, because it is the task of
the Mail::Box::Threads object to construct it.

As OPTIONS, you can specify

=over 4

=item * message =E<gt> OBJECT

The message which is stored in this node.  The message must be a
Mail::Box::Message.

=item * messageID =E<gt> MESSAGE-ID

The messageID which is stored in this node.  Do only specify it when
you don't have the message yet.

=item * dummy_type =E<gt> CLASS

When we need a dummy, which type should it become.

=back

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    if(my $message = $args->{message})
    {   push @{$self->{MBT_messages}}, $message;
        $self->{MBT_msgid} = $args->{msgid} || $message->messageID;
    }
    elsif(my $msgid = $args->{msgid})
    {   $self->{MBT_msgid} = $msgid;
    }
    else
    {   croak "Need to specify message or message-id";
    }

    $self->{MBT_dummy_type} = $args->{dummy_type};
    $self;
}

#-------------------------------------------

=item message

Get the message which is stored in this thread-node.  However: the same
message may be located in many folders at the same time, which on turn may
be controled by the same thread-manager.

In SCALAR context, you will get the first undeleted instance of the
message.  If all instances are flagged for deletion, then you get
the first.  When the open folders only contain references to the message,
but no instance, you get a dummy message (Mail::Box::Message::Dummy).

In LIST context, you get all instances of the message, found till now.

Examples:

   my $threads = $mgr->threads(folders => [$draft, $sent]);
   my $node    = $draft->message(1)->thread;

   foreach my $instance ($node->message)
   {   print "Found in ", $instance->folder, ".\n";
   }
   print "Best is ", scalar $node->message, ".\n";
   
=cut

sub message()
{   my $self = shift;

    unless($self->{MBT_messages})
    {   return () if wantarray;

        my $dummy = $self->{MBT_dummy_type}->new($self->{MBT_msgid});
        push @{$self->{MBT_messages}}, $dummy;
        return $dummy;
    }

    my @messages = @{$self->{MBT_messages}};
    return @messages    if wantarray;
    return $messages[0] if @messages==1;

    foreach (@messages)
    {   return $_ unless $_->deleted;
    }

    $messages[0];
}

#-------------------------------------------

=item addMessage MESSAGE

Add one message to the thread-node.  If the node is filled with a dummy,
then that one is replaced.  In other cases, the messages is added to the
end of the list.

=cut

sub addMessage($)
{   my ($self, $message) = @_;
 
    return $self->{MBT_messages} = [ $message ]
        if $self->isDummy;

    push @{$self->{MBT_messages}}, $message;
    $message;
}

#-------------------------------------------

=item isDummy

Returns whether this node has no messages (yet): is a hole in a
thread.

=cut

sub isDummy()
{   my $self = shift;
    !defined $self->{MBT_messages} || $self->{MBT_messages}[0]->isDummy;
}

#-------------------------------------------

=item messageID

Return the message-id related to this thread-node.  Each of the messages
listed in this node will have the same ID.

=cut

sub messageID() { shift->{MBT_msgid} }

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

=item * 'REPLY'

This relation was directly derived from an `in-reply-to' message header
field.  The relation is very sure.

=item * 'REFERENCE'

This relation is based on information found in a `Reference' message
header field.  One message may reference a list of messages which
precede it in the thread.  Let's hope they are stored in the right
order.

=item * 'GUESS'

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

=item follows THREAD, QUALITY

Register that the current thread is a reply on this
specified THREAD. The QUALITY of the relation is specified by the
second argument.

The relation may be specified more than once, but there can be only one.
Once a reply (QUALITY equals C<REPLY>) is detected, that value will be
kept.

=cut

sub follows($$)
{   my ($self, $thread, $how) = @_;

    unless(exists $self->{MBT_parent} && $self->{MBT_quality} eq 'REPLY')
    {   $self->{MBT_parent}  = $thread;
        $self->{MBT_quality} = $how;
    }

    $self;
}

#-------------------------------------------

=item followedBy THREADS

Register that the THREADS are follow-ups to this message.
There may be more than one of these follow-ups which are not related to
each-other in any other way than sharing the same parent.

If the same relation is defined more than ones, this will not cause
duplication of information.

=cut

sub followedBy(@)
{   my $self = shift;
    $self->{MBT_followUps}{$_->messageID} = $_ foreach @_;
    $self;
}

#-------------------------------------------

=item followUps

=item sortedFollowUps [PREPARE [,COMPARE]]

Returns the list of follow-ups to this thread-node.  This list
contains parsed, not-parsed, and dummy messages.

The C<sortedFollowUps()> returns the same list, but then sorted
(by default based on an estimated time of the reply see C<startTimeEstimate()>
and Mail::Box::sort).

=cut

sub followUps()
{   my $self    = shift;
    $self->{MBT_followUps} ? values %{$self->{MBT_followUps}} : ();
}

sub sortedFollowUps()
{   my $self    = shift;
    my $prepare = shift || sub {shift->startTimeEstimate||0};
    my $compare = shift || sub {(shift) <=> (shift)};
    Mail::Box->sort($prepare, $compare, $self->followUps);
}

#-------------------------------------------

=back

=head2 Actions on whole threads

Some conveniance methods are added to threads, to simplify retreiving
knowledge from it.

=over 4

=item recurseThread CODE-REF

Execute a function for all sub-threads.  If the subroutine returns true,
sub-threads are visited, too.  Otherwise, this branch is aborted.  The
routine is called with the thread-node as only argument.

=cut

sub recurseThread($)
{   my ($self, $code) = @_;
    $code->($self) || return $self;
    $_->recurseThread($code) or last foreach $self->followUps;
    $self;
}

#-------------------------------------------

=item totalSize

Sum the size of all the messages in the thread.

=cut

sub totalSize()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {$total += shift->{MBT_messages}[0]->size; 1} );
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
    return $self->message->label('folded') || 0
        unless @_;

    my $fold = shift;
    $_->setLabel(folded => $fold) foreach $self->message;
    $fold;
}

#-------------------------------------------

=item threadToString [CODE]

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

The optional CODE argument is a reference to a routine which will be called
for each message in the thread.  The routine will be called with the
message as first argument.  The default shows the subject of the message.
In the example above, this routine is called seven times.

=cut

sub threadToString(;$$$)   # two undocumented parameters for layout args
{   my $self    = shift;
    my $code    = shift || sub {shift->head->get('subject')};
    my ($first, $other) = (shift || '', shift || '');
    my $message = $self->message;
    my @follows = $self->sortedFollowUps;

    my @out;
    if($self->folded)
    {   my $text = $code->($message) || '';
        chomp $text;
        return "    $first [" . $self->nrMessages . "] $text\n";
    }
    elsif($message->isDummy)
    {   $first .= $first ? '-*-' : ' *-';
        return (shift @follows)->threadToString($code, $first, "$other   " )
            if @follows==1;

        push @out, (shift @follows)->threadToString($code, $first, "$other | " )
            while @follows > 1;
    }
    else
    {   my $text  = $code->($message) || '';
        chomp $text;
        my $size  = $message->shortSize;
        @out = "$size$first $text\n";
        push @out, (shift @follows)
                       ->threadToString($code, "$other |-", "$other | " )
            while @follows > 1;
    }

    push @out, (shift @follows)->threadToString($code, "$other `-","$other   " )
        if @follows;

    join '', @out;
}

#-------------------------------------------

=item startTimeEstimate

Guess when this thread was started.  Each message contains a various
date specifications (each with various uncertainties, because of
timezones and out-of-sync clocks), one of which is taken as timestamp for
the message.  This method returns the timestamp of this message (message
contained in this node of the thread), but when this is a dummy the
lowest of the replies.

=cut

sub startTimeEstimate()
{   my $self = shift;

    return $self->message->timestamp
        unless $self->isDummy;

    my $earliest;
    foreach ($self->followUps)
    {   my $stamp = $_->startTimeEstimate;

        $earliest = $stamp if    !defined $earliest
                              || (defined $stamp && $stamp < $earliest);
    }

    $earliest;
}

#-------------------------------------------

=item endTimeEstimate

Returns a guess as to when the thread has ended (although you never
know for sure whether there fill follow messages in the future).

=cut

sub endTimeEstimate()
{   my $self = shift;

    return $self->message->timestamp
        unless $self->isDummy;

    my $latest;
    $self->recurseThread
     (  sub { my $node = shift;
              unless($node->isDummy)
              {   my $stamp = $node->message->timestamp;
                  $latest = $stamp if !$latest || $stamp > $latest;
              }
            }
     );

    $latest;
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

A Mail::Box::Threads-object is created by the Mail::Box::Manager, using
its C<threads()> method.  Each object can monitor the thread-relations
between messages in one or more folders.  When more than one folder
is specified, the messages are merged while reading the threads, although
nothing changes in the folder-structure.  Adding and removing folders
which have to be maintained is permitted at any moment, although may
be quite costly in performance.

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
        |       +-----msg1  //        /
        |       +-----msg2-'/        /
        |                  /        /
        `-----folder2     /        /
                |        /        /
                +-----msg2       /
                +-----msg3------'

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

The following reports the Mail::Box::Thread object which is related
to a message:

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

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.321

=cut

1;
