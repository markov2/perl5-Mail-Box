
use strict;

=head1 NAME

Mail::Box::Thread - one discussion thread in a folder

=head1 SYNOPSIS

   my $thread = $message->thread;
   $thread->printThread;

=head1 DESCRIPTION

Read L<Mail::Box::Manager> and L<Mail::Box::Threads> first.

A (message-)I<thread> is a message, with the messages which followed in
reply on that message.  And the messages with replied the messages
which replied the original message.  And so on.  Some threads are only
one message (never replied to), some threads are very long.

=cut

###
### Mail::Box::Thread
###

package Mail::Box::Thread;

#-------------------------------------------

=head1 Mail::Box::Thread

=over 4

=item new ARGS

The instatiation of a thread is done by its subclasses.  You will not
call this method by yourself (it is even not implemented).

In the current implementation, there are no options added to the
C<Mail::Box::Message>'s object creation.

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

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.100

=cut

1;
