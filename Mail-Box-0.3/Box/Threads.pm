
package Mail::Box::Threads;

use strict;
use v5.6.0;
our $VERSION = v0.3;

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

This module maintains an easily accessable structure containing information
about threads.  Each thread is maintained while a folder is open.
The structure consists of message, and a list of replies.  A reply can
be a single message or a thread by itself.

=head1 PUBLIC INTERFACE

=over 4

=item new ARGS

The construction of a Mail::Box::Threads accepts the following options:

=over 4

=item * dummy_type => CLASS

Of which class are dummy messages?  Usually, this needs to be the
C<message_type> of the folder prepended with C<::Dummy>.  This will also
be the default.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->registerHeaders(qw/message-id in-reply-to references/);

    $self->{MBT_dummy_type} = $args->{dummy_type}
                           || $self->{MB_message_type} . '::Dummy';

    $self;
}

#-------------------------------------------

=item messageWithId MESSAGE-ID [MESSAGE]

Returns (and first sets) the message which has a certain id.

=cut

sub messageWithId($;$)
{   my ($self, $msgid) = (shift,shift);
    @_ ? ($self->{MBT_ids}{$msgid} = shift) : $self->{MBT_ids}{$msgid};
}

#-------------------------------------------

=item allMessageIDs

Returns a list of I<all> messages/message-ids in the folder, including
those which are to be deleted.

Example:
    my @ids = grep {not $_->deleted}
                  $folder->allMessageIDs;

=cut

sub allMessageIDs() { keys %{shift->{MBT_ids}} }

#-------------------------------------------

=item addToThread MESSAGE

Add a message to a discussion-thread.  It does not matter whether you
have done this before (although this information should not conflict
with the thread-information found till now).

=cut

sub addToThread($)
{   my ($self, $message) = @_;
    my $msgid   = $message->messageID;
    my $replies = $message->in_reply_to;

    $self->follows($replies, $msgid) if $replies;

    my @refs  = $message->references;
    push @refs, $msgid;

    my $start = shift @refs;
    $self->registerThread($start) unless $replies;

    while(my $child = shift @refs)
    {   $self->unregisterThread($child) if $self->isThreadStart($child);
        $self->follows($start, $child);
        $start = $child;
    }

    $self;
}

#-------------------------------------------

=item follows MESSAGE, MESSAGE

Register a follow-up from message to the other.

Example:
   $folder->follows($question, $answer);

=cut

sub follows($$)
{   my ($self, $parent, $child) = @_;

#warn "$parent follows $child";
    $self->messageWithId($parent, $self->{MBT_dummy_type}->new($parent))
        unless $self->messageWithId($parent);

    $self->messageWithId($parent)->addFollowUp($child);
    $self;
}

#-------------------------------------------

=item registerThread MESSAGE|MESSAGE-ID

=item unregisterThread MESSAGE|MESSAGE-ID

Register/Unregister a message or message-id to be (not to be) the start of
a thread.  This does not mean that the message is the top of a thread for
sure, because not all mail-packages are careful in handling references.
Call C<lintThreads> to reduce the discrepancies in threads further.

=cut

sub registerThread($)
{   my ($self, $message) = @_;
    my $id;
    if(ref $message && $message->isa('Mail::Box::Message'))
    {   $id = $message->messageID;
    }
    else
    {   $id = $message;
        $message = $self->messageWithId($id);
    }

#print "register $id\n";
    $self->{MBT_threads}{$id} = $message;
}

sub unregisterThread($)
{   my ($self, $thread) = @_;
    $thread    = $thread->messageID
        if ref $thread && $thread->isa('Mail::Box::Message');

print "unregister $thread\n";
    delete $self->{MBT_threads}{$thread};
}

#-------------------------------------------

=item lintThreads

Improve the quality of thread discovery.  Running lint-ing might be
time-consuming, so is only run on explicit request.  You do not have
to re-run lint once you have read the file: all further modifications
to the folder will maintain correct threads.

Example:
    my $folder = Mail::Box::File->new->lintThreads;

=cut

sub lintThreads()
{   my Mail::Box $self   = shift;

    # Try to relate messages based on
    #    Subject
    #    Sender-Receiver
    #    Content
    # ... to be implemented ...

    $self;
}
 
#-------------------------------------------

=item isThreadStart MESSAGE|MESSAGE-ID

Check whether the message is registered as being a start for threads.

Example:
    if($folder->isThreadStart($folder->message(3)) {...};

=cut

sub isThreadStart($)
{   my ($self, $id) = @_;

    $id = $id->messageID
        if ref $id && $id->isa('Mail::Box::Message');

    exists $self->{MBT_threads}{$id};
}

#-------------------------------------------

=item threads

Returns a list of all threads discovered so far.

Example:
   print $_->nrMessages foreach $folder->threads;

=cut

sub threads() { values %{shift->{MBT_threads}} }

###
### Mail::Box::Thread
###

#-------------------------------------------

=back

=head1 Mail::Box::Thread

A thread implements a linked list of messages which are a logical
sequence.  There are two sides to threads: primarly the relations between
messages, and secondary the way they are presented on the screen.

=cut

package Mail::Box::Thread;
use Carp;

sub new(@) { (bless {}, shift)->init(@_) }

sub init($)
{   my $self = shift;
    $self->{MBT_followups} = [];
    $self;
}

sub folder()
{   confess "Extentions of a thread shall implement the folder() method.";
}


#-------------------------------------------

=item addFollowUp MESSAGE | MESSAGE-ID

=item addFollowUps [MESSAGE | MESSAGE-ID]*

Add one/multiple messages or message-ids to the list of messages which
are send as follow-up on this message.  This information is used to
recognize descussion threads.  Duplicates are ignored.

Example:
   $message1->addFollowUp($message2);
   $message1->addFollowUp($message2->messageID);

=cut

sub addFollowUp($)
{   my Mail::Box::Message $self     = shift;

    my $followup = shift;
    $followup = $followup->messageID
        if ref $followup && $followup->isa('Mail::Box::Message');

    push @{$self->{MBT_followups}}, $followup
        unless grep {$_ eq $followup} @{$self->{MBT_followups}};

    $self;
}

sub addFollowUps($)
{   my $self = shift;
    $self->addFollowUp($_) foreach @_;
    $self;
}

#-------------------------------------------

=item followUps

Return the whole list of follow-ups.

Examples:
    my @replies = $message->followUps;
    print scalar $message->followUps, " replies.\n";

=cut

sub followUps()
{   my $self = shift;

    if(wantarray)
         { return exists $self->{MBT_followups}
                ? @{$self->{MBT_followups}}
                : ()
         }
    else { return exists $self->{MBT_followups}
                ? scalar @{$self->{MBT_followups}}
                : 0
          }
}


#-------------------------------------------

=item subThreads

Return the subThreads of this thread.

=cut

sub subThreads()
{   my $self   = shift;
    my $folder = $self->folder;
    $self->{MBT_subthreads}
       = [ map {$folder->messageWithId($_)} $self->followUps ]
          unless exists $self->{MBT_subthreads};

    @{$self->{MBT_subthreads}};
}

#-------------------------------------------

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

This code is alpha, version 0.3

=cut

1;
