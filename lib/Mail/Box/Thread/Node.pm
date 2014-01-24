
use strict;
package Mail::Box::Thread::Node;
use base 'Mail::Reporter';

use Carp;

=chapter NAME

Mail::Box::Thread::Node - one node in a message thread

=chapter SYNOPSIS

 my $node = Mail::Box::Thread::Node->new;
 $node->addMessage($message);
 ...

=chapter DESCRIPTION

The C<Mail::Box::Thread::Node> maintains one node in the linked list of
threads.  Each node contains one message, and a list of its follow-ups.
Next to that, it refers to its own ancestor and contains information
about the trustworthiness of that relationship.

To complicate things a little, because the thread-manager can maintain
multiple folders, and merge there content, you may find the same message
in more folders.  All versions of the same message (based on message-id)
are stored in the same node.

=chapter METHODS

=c_method new %options

You will not call this method yourself. The M<Mail::Box::Thread::Manager>
object will call it to construct C<Mail::Box::Thread::Node> objects.
Either a C<message> or a C<messageId> must be supplied.

=option  message MESSAGE
=default message undef
The MESSAGE which is stored in this node.  The message
must be a Mail::Box::Message.

=option  messageId MESSAGE-ID
=default messageId undef
The MESSAGE-ID for the message which is stored in this node.  Only
specify it when you don't have the message yet.

=option  dummy_type CLASS
=default dummy_type undef
Indicates the class name of dummy messages. Dummy messages are
placeholders in a M<Mail::Box::Thread::Manager> data structure.

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    if(my $message = $args->{message})
    {   push @{$self->{MBTN_messages}}, $message;
        $self->{MBTN_msgid} = $args->{msgid} || $message->messageId;
    }
    elsif(my $msgid = $args->{msgid})
    {   $self->{MBTN_msgid} = $msgid;
    }
    else
    {   croak "Need to specify message or message-id";
    }

    $self->{MBTN_dummy_type} = $args->{dummy_type};
    $self;
}

#-------------------------------------------

=section The thread node

=method message
Get the message which is stored in this thread node.  NOTE: the same
message may be located in many folders at the same time, and these
folders may be controlled by the same thread manager.

In scalar context, this method returns the first instance of the
message that is not deleted. If all instances are flagged for deletion,
then you get the first deleted message. When the open folders only
contain references to the message, but no instance, you get a dummy
message (see M<Mail::Message::Dummy>).

In list context, all instances of the message which have been found are
returned.

=examples

 my $threads = $mgr->threads(folders => [$draft, $sent]);
 my $node    = $draft->message(1)->thread;

 foreach my $instance ($node->message) {
    print "Found in ", $instance->folder, ".\n";
 }

 print "Subject is ", $node->message->subject, ".\n";
   
=cut

sub message()
{   my $self = shift;

    unless($self->{MBTN_messages})
    {   return () if wantarray;

        my $dummy = $self->{MBTN_dummy_type}->new
          ( messageId =>$self->{MBTN_msgid}
          );

        push @{$self->{MBTN_messages}}, $dummy;
        return $dummy;
    }

    my @messages = @{$self->{MBTN_messages}};
    return @messages    if wantarray;
    return $messages[0] if @messages==1;

    foreach (@messages)
    {   return $_ unless $_->isDeleted;
    }

    $messages[0];
}

=method addMessage $message
Add one message to the thread node.  If the node contains a dummy, then
the dummy is replaced. Otherwise, the messages is added to the end of the
list.
=cut

sub addMessage($)
{   my ($self, $message) = @_;
 
    return $self->{MBTN_messages} = [ $message ]
        if $self->isDummy;

    push @{$self->{MBTN_messages}}, $message;
    $message;
}

=method isDummy
Returns true if the message is a dummy. A dummy is a "hole" in a thread
which has follow-ups but does not have a message.
=cut

sub isDummy()
{   my $self = shift;
    !defined $self->{MBTN_messages} || $self->{MBTN_messages}[0]->isDummy;
}

=method messageId
Return the message-id related to this thread node.  Each of the messages
listed in this node will have the same ID.
=cut

sub messageId() { shift->{MBTN_msgid} }

=method expand [BOOLEAN]
Returns whether this (part of the) folder has to be shown expanded or not.
This is simply done by a label, which means that most folder types can
store this.
=cut

sub expand(;$)
{   my $self = shift;
    return $self->message->label('folded') || 0
        unless @_;

    my $fold = not shift;
    $_->label(folded => $fold) foreach $self->message;
    $fold;
}

sub folded(;$)    # compatibility <2.0
{  @_ == 1 ? shift->expand : shift->expand(not shift) }

#-------------------------------------------
=section The thread order

=method repliedTo
Returns the message(s) to which the message in this node replies. In
scalar context, this method will return the message to which the message
in this node replies. This message object may be a dummy message.

If the message seems to be the first message of a thread, the value C<undef>
is returned.  (Remember that some MUA are not adding reference information
to the message's header, so you can never be sure a message is the
start of a thread)

In list context, this method returns a second string value indicating the
confidence that the messages are related.  When extended thread discovery
is enabled, then some heuristics are applied to determine if messages are
related. Values for the STRING may be:

=over 4

=item * C<'REPLY'>

This relation was directly derived from an `in-reply-to' message header
field. The relation has a high confidence.

=item * C<'REFERENCE'>

This relation is based on information found in a `Reference' message
header field.  One message may reference a list of messages which
precede it in the thread. The heuristic attempts to determine
relationships between messages assuming that the references are in order.
This relation has a lower confidence.

=item * C<'GUESS'>

The relation is a big guess, with low confidence.  It may be based on
a subject which seems to be related, or commonalities in the message's
body.

=back

More constants may be added later.

=examples

 my $question = $answer->repliedTo;
 my ($question, $quality) = $answer->repliedTo;
 if($question && $quality eq 'REPLY') { ... };

=cut

sub repliedTo()
{   my $self = shift;

    return wantarray
         ? ($self->{MBTN_parent}, $self->{MBTN_quality})
         : $self->{MBTN_parent};
}

=method follows $thread, $quality
Register that the current thread is a reply to the specified $thread. The
$quality of the relation is specified by the second argument.  The method
returns C<undef> if the link is not accepted in order to avoid circular
references.

The relation may be specified more than once, but only the most confident
relation is used. For example, if a reply ($quality equals C<REPLY>) is
specified, later calls to the follow method will have no effect. If
C<follows> is called with a $quality that matches the current quality, the
new thread overrides the previous.
=cut

sub follows($$)
{   my ($self, $thread, $how) = @_;
    my $quality = $self->{MBTN_quality};

    # Do not create cyclic constructs caused by erroneous refs.

    my $msgid = $self->messageId;       # Look up for myself, upwards in thread
    for(my $walker = $thread; defined $walker; $walker = $walker->repliedTo)
    {   return undef if $walker->messageId eq $msgid;
    }

    my $threadid = $thread->messageId;  # a->b and b->a  (ref order reversed)
    foreach ($self->followUps)
    {   return undef if $_->messageId eq $threadid;
    }

    # Register

    if($how eq 'REPLY' || !defined $quality)
    {   $self->{MBTN_parent}  = $thread;
        $self->{MBTN_quality} = $how;
        return $self;
    }
    
    return $self if $quality eq 'REPLY';

    if($how eq 'REFERENCE' || ($how eq 'GUESS' && $quality ne 'REFERENCE'))
    {   $self->{MBTN_parent}  = $thread;
        $self->{MBTN_quality} = $how;
    }

    $self;
}

=method followedBy $threads
Register that the $threads are follow-ups to this message. These
follow-ups need not be related to each other in any way other than
sharing the same parent.

Defining the same relation more than once will not cause information to
be duplicated.

=cut

sub followedBy(@)
{   my $self = shift;
    $self->{MBTN_followUps}{$_->messageId} = $_ foreach @_;
    $self;
}

=method followUps
Returns the list of follow-ups to this thread node.  This list
may contain parsed, not-parsed, and dummy messages.
=cut

sub followUps()
{   my $self    = shift;
    $self->{MBTN_followUps} ? values %{$self->{MBTN_followUps}} : ();
}

=method sortedFollowUps [$prepare, [$compare]]
Returns the list of M<followUps()>, but sorted.  By default
sorting is based on the estimated time of the reply. See
startTimeEstimate().
=cut

sub sortedFollowUps()
{   my $self    = shift;
    my $prepare = shift || sub {shift->startTimeEstimate||0};
    my $compare = shift || sub {(shift) <=> (shift)};

    my %value   = map { ($prepare->($_) => $_) } $self->followUps;
    map { $value{$_} } sort {$compare->($a, $b)} keys %value;
}

#-------------------------------------------
=section On the whole thread

Some convenience methods are added to threads, to simplify retrieving
information from it.

=method threadToString [CODE]

Translate a thread into a string. The string will contain at least one
line for each message which was found, but tries to fold dummies.  This
is useful for debugging, but most message readers will prefer to
implement their own thread printer.

The optional CODE argument is a reference to a routine which will be called
for each message in the thread.  The routine will be called with the
message as the first argument.  The default shows the subject of the message.
In the first example below, this routine is called seven times.

=examples

 print $node->threadToString;

may result in

 Subject of this message
 |- Re: Subject of this message
 |-*- Re: Re: Subject of this message
 | |- Re(2) Subject of this message
 | |- [3] Re(2) Subject of this message
 | `- Re: Subject of this message (reply)
 `- Re: Subject of this message

The `*' represents a missing message (a "dummy" message).  The `[3]'
presents a folded thread with three messages.

 print $node->threadToString(\&show);

 sub show($) {
    my $message = shift;
    my $subject = $message->head->get('subject');
    length $subject ? $subject : '<no subject>';
 }

=cut

sub threadToString(;$$$)   # two undocumented parameters for layout args
{   my $self    = shift;
    my $code    = shift || sub {shift->head->study('subject')};
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

=method startTimeEstimate
Returns a guess as to when the thread was started.  Each message contains
various date specifications (each with various uncertainties resulting
from timezones and out-of-sync clocks). One of these date specifications
is used as the timestamp for the message. If the node contains a dummy
message the lowest timestamp of the replies is returned. Otherwise the
estimated timestamp of the node's message is returned.
=cut

sub startTimeEstimate()
{   my $self = shift;

    return $self->message->timestamp
        unless $self->isDummy;

    my $earliest;
    foreach ($self->followUps)
    {   my $stamp = $_->startTimeEstimate;

        $earliest = $stamp
	    if !defined $earliest || (defined $stamp && $stamp < $earliest);
    }

    $earliest;
}

=method endTimeEstimate
Returns a guess as to when the thread has ended (although you never
know for sure whether there fill follow messages in the future).
=cut

sub endTimeEstimate()
{   my $self = shift;

    my $latest;
    $self->recurse
     (  sub { my $node = shift;
              unless($node->isDummy)
              {   my $stamp = $node->message->timestamp;
                  $latest = $stamp if !$latest || $stamp > $latest;
              }
            }
     );

    $latest;
}

=method recurse CODE
Execute a function for all sub-threads.  If the subroutine returns true,
sub-threads are visited recursively. Otherwise, the current branch
traversal is aborted. The routine is called with the thread-node as the
only argument.
=cut

sub recurse($)
{   my ($self, $code) = @_;

    $code->($self) or return $self;

    $_->recurse($code) or last
        foreach $self->followUps;

    $self;
}

=method totalSize
Returns the sum of the size of all the messages in the thread.
=cut

sub totalSize()
{   my $self  = shift;
    my $total = 0;

    $self->recurse
     ( sub {
          my @msgs = shift->messages;
          $total += $msgs[0]->size if @msgs;
          1;}
     );

    $total;
}

=method numberOfMessages
Number of messages in the thread starting at the current thread node, but
not counting the dummies.
=cut

sub numberOfMessages()
{   my $self  = shift;
    my $total = 0;
    $self->recurse( sub {++$total unless shift->isDummy; 1} );
    $total;
}

sub nrMessages() {shift->numberOfMessages}  # compatibility

=method threadMessages
Returns all the messages in the thread starting at the current thread
node.  This list will not include dummies.

=example
 my @t = $folder->message(3)
                ->threadStart
                ->threadMessages;
=cut

sub threadMessages()
{   my $self = shift;
    my @messages;
    $self->recurse
     ( sub
       { my $node = shift;
         push @messages, $node->message unless $node->isDummy;
         1;
       }
     );

    @messages;
}


=method ids
Returns all the ids in the thread starting at the current thread node.

=examples
 $newfolder->addMessages($folder->ids($thread->ids));
 $folder->delete($thread->ids);
=cut

sub ids()
{   my $self = shift;
    my @ids;
    $self->recurse( sub {push @ids, shift->messageId} );
    @ids;
}

#-------------------------------------------

=section Error handling

=cut


1;
