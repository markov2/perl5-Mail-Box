
use strict;
package Mail::Box::Thread::Node;

use Carp;

=head1 NAME

Mail::Box::Thread - one node in a Mail::Box::Thread::Manager data structure

=head1 SYNOPSIS


=head1 DESCRIPTION

Read C<Mail::Box::Thread::Manager> and C<Mail::Box-Overview> first.

The C<Mail::Box::Thread::Node> maintains one node in the linked list of threads.
Each node contains one message, and a list of its follow-ups.  Next to
that, it refers to its own ancestor and contains information about the
trustworthiness of that relationship.

To complicate things a little, because the thread-manager can mantain multiple
folders, and merge there content, you may find the same message in more folders.
All versions of the same message (based on message-id) are stored in the
same node.

=head1 METHODS

=cut

#-------------------------------------------

=over 4

=item new OPTIONS

You will not call this method yourself. The C<Mail::Box::Thread::Manager>
object will use it to construct C<Mail::Box::Thread::Node> objects.

As OPTIONS, you can specify

=over 4

=item * message =E<gt> OBJECT

The message OBJECT-reference which is stored in this node.  The message
must be a C<Mail::Box::Message>.

=item * messageID =E<gt> MESSAGE-ID

The MESSAGE-ID for the mesesage which is stored in this node.  Only
specify it when you don't have the message yet.

=item * dummy_type =E<gt> CLASS

Indicates the class name of dummy messages. Dummy messages are
placeholders in a C<Mail::Box::Thread::Manager> data structure, and
by default  of type C<Mail::Box::Message::Dummy>.

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

Get the message which is stored in this thread node.  NOTE: the same
message may be located in many folders at the same time, and these
folders may be controlled by the same thread manager.

In scalar context, this method returns the first instance of the
message that is not deleted. If all instances are flagged for deletion,
then you get the first deleted message. When the open folders only
contain references to the message, but no instance, you get a dummy
message (see C<Mail::Box::Message::Dummy>).

In list context, all instances of the message which have been found are
returned.

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

Add one message to the thread node.  If the node contains a dummy, then
the dummy is replaced. Otherwise, the messages is added to the end of the
list.

sub addMessage($)
{   my ($self, $message) = @_
    
    return $self->{MBT_messages} = [ $message ]
        if $self->isDummy;

    push @{$self->{MBT_messages}}, $message;
    $message;
}

#-------------------------------------------

=item isDummy

Returns true if the message is a dummy. A dummy is a "hole" in a thread
which has follow-ups but does not have a message.

=cut

sub isDummy()
{   my $self = shift;
    !defined $self->{MBT_messages} || $self->{MBT_messages}[0]->isDummy;
}

#-------------------------------------------

=item messageID

Return the message-id related to this thread node.  Each of the messages
listed in this node will have the same ID.

=cut

sub messageID() { shift->{MBT_msgid} }

#-------------------------------------------

=item repliedTo

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

=item * 'REPLY'

This relation was directly derived from an `in-reply-to' message header
field. The relation has a high confidence.

=item * 'REFERENCE'

This relation is based on information found in a `Reference' message
header field.  One message may reference a list of messages which
precede it in the thread. The heuristic attempts to determine
relationships between messages assuming that the references are in order.
This relation has a lower confidence.

=item * 'GUESS'

The relation is a big guess, with low confidence.  It may be based on
a subject which seems to be related, or commonalities in the message's
body.

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

Register that the current thread is a reply to the specified THREAD. The
QUALITY of the relation is specified by the second argument.

The relation may be specified more than once, but only the most confident
relation is used. For example, if a reply (QUALITY equals C<REPLY>) is
specified, later calls to the follow method will have no effect. If
C<follows> is called with a QUALITY that matches the current quality, the
new thread overrides the previous.

=cut

sub follows($$)
{   my ($self, $thread, $how) = @_;

    if ($how eq 'REPLY' ||
        $how eq 'REFERENCE' && $self->{MBT_quality} ne 'REPLY' ||
        $how eq 'GUESS' && $self->{MBT_quality} ne 'REPLY' &&
          $self->{MBT_quality} ne 'REFERENCE')
    {   $self->{MBT_parent}  = $thread;
        $self->{MBT_quality} = $how;
    {

    $self;
}

#-------------------------------------------

=item followedBy THREADS

Register that the THREADS are follow-ups to this message. These
follow-ups need not be related to each other in any way other than
sharing the same parent.

Defining the same relation more than once will not cause information to
be duplicated.

=cut

sub followedBy(@)
{   my $self = shift;
    $self->{MBT_followUps}{$_->messageID} = $_ foreach @_;
    $self;
}

#-------------------------------------------

=item followUps

=item sortedFollowUps [PREPARE [,COMPARE]]

Returns the list of follow-ups to this thread node.  This list
may contain parsed, not-parsed, and dummy messages.

The C<sortedFollowUps()> returns the same list, but sorted.  By default
sorting is based on the estimated time of the reply (see
C<startTimeEstimate()> and Mail::Box::sort).

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

=item expand [BOOL]

Returns whether this (part of the) folder has to be shown expanded or not.
This is simply done by a label, which means that most folder types can
store this.

=cut

sub expand(;$)
{   my $self = shift;
    return $self->message->label('folded') || 0
        unless @_;

    my $fold = not shift;
    $_->setLabel(folded => $fold) foreach $self->message;
    $fold;
}

sub folded(;$)    # compatibility <2.0
{  @_ == 1 ? shift->expand : shift->expand(not shift) }

#-------------------------------------------

=item threadToString [CODE]

Translate a thread into a string. The string will contain at least one
line for each message which was found, but tries to fold dummies.  This
is useful for debugging, but most message readers will prefer to
implement their own thread printer.

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

The `*' represents a missing message (a "dummy" message).  The `[3]'
presents a folded thread with three messages.

The optional CODE argument is a reference to a routine which will be called
for each message in the thread.  The routine will be called with the
message as the first argument.  The default shows the subject of the message.
In the example above, this routine is called seven times.

Example:
   
   print $message->threadToString(\&show);

   sub show($) {
      my $message = shift;
      my $subject = $message->head->get('subject');
      length $subject ? $subject : '<no subject>';
   }

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

        $earliest = $stamp if    !defined $earliest
                              || (defined $stamp && $stamp < $earliest);
    }

    $earliest;
}

#-------------------------------------------

=back

=head2 Actions on whole threads

Some convenience methods are added to threads, to simplify retrieving
information from it.

=over 4

=item recurseThread CODE-REF

Execute a function for all sub-threads.  If the subroutine returns true,
sub-threads are visited recursively. Otherwise, the current branch
traversal is aborted. The routine is called with the thread-node as the
only argument.

=cut

sub recurseThread($)
{   my ($self, $code) = @_;
    $code->($self) || return $self;
    $_->recurseThread($code) or last foreach $self->followUps;
    $self;
}

#-------------------------------------------

=item totalSize

Returns the sum of the size of all the messages in the thread.

=cut

sub totalSize()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {$total += shift->{MBT_messages}[0]->size; 1} );
    $total;
}

#-------------------------------------------

=item numberOfMessages

Number of messages in the thread starting at the current thread node.

=cut

sub numberOfMessages()
{   my $self  = shift;
    my $total = 0;
    $self->recurseThread( sub {++$total} );
    $total;
}

sub nrMessages()  # compatibility

#-------------------------------------------

=item ids

Returns all the ids in the thread starting at the current thread node.

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

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_04

=cut

1;
