
use strict;
use warnings;

package Mail::Box::Message;
use base 'Mail::Message';

use Date::Parse;
use Scalar::Util 'weaken';

=head1 NAME

Mail::Box::Message - manage one message within a mail-folder

=head1 SYNOPSIS

 # Usually these message objects are created indirectly
 use Mail::Box::Manager;
 my $manager = Mail::Box::Manager->new;
 my $folder  = $manager->open(folder => 'Mail/Drafts');
 my $msg     = $folder->message(1);
 $msg->delete;
 $msg->size;   # and much more

=head1 DESCRIPTION

These pages do only describe methods which relate to folders.  If you
access the knowledge of a message, then read Mail::Message.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message's body and head objects may change.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=option  folder FOLDER
=default folder <required>

(obligatory) The folder where this message appeared in.  The argument is
an instance of (a sub-class of) a Mail::Box.

=option  body_type CODE|CLASS
=default body_type <from folder>

If the body of a message is used delay-loaded, the message must what type
of message to become when it finally gets parsed.  The folder which is
delaying the load must specify the algorithm to determine that type.

=option  deleted BOOLEAN
=default deleted <false>

Is the file deleted from the start?

=option  size INTEGER
=default size undef

The size of the message, which includes head and body, but without the
message separators which may be used by the folder type.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_deleted}    = $args->{deleted}   || 0;

    $self->{MBM_body_type}  = $args->{body_type}
        if exists $args->{body_type};

    $self->{MBM_folder}     = $args->{folder};
    weaken($self->{MBM_folder});

    return $self if $self->isDummy;

    $self;
}

#-------------------------------------------

=head2 Constructing a Message

=cut

#-------------------------------------------

=method coerce MESSAGE

Coerce a message to be included in a folder.  The folder itself
is not specified, but the type of the message is transformed correctly.
The coerced version of the message is returned.  When no changes had
to be made, the original message is returned.

=cut

sub coerce($)
{   my ($class, $message) = @_;
    return bless $message, $class
        if $message->isa(__PACKAGE__);

    my $coerced = $class->SUPER::coerce($message);
    $coerced->{MBM_deleted} = 0;
    $coerced;
}

#-------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

=method folder [FOLDER]

In with folder did we detect this message/dummy?  This is a reference
to the folder-object.

=cut

sub folder(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MBM_folder} = shift;
        weaken($self->{MBM_folder});
        $self->modified(1);
    }
    $self->{MBM_folder};
}

#-------------------------------------------

=method seqnr [INTEGER]

Get the number of this message is the current folder.  It starts counting
from zero.  Do not change the number.

=cut

sub seqnr(;$)
{   my $self = shift;
    @_ ? $self->{MBM_seqnr} = shift : $self->{MBM_seqnr};
}

#-------------------------------------------

=method copyTo FOLDER

Copy the message to the indicated opened FOLDER, without deleting the
original.  The coerced message (the copy in the desitnation folder) is
returned.

=example

 my $draft = $mgr->open(folder => 'Draft');
 $message->copyTo($draft);

=cut

sub copyTo($)
{   my ($self, $folder) = @_;
    $folder->addMessage($self->clone);
}

#-------------------------------------------

=method moveTo FOLDER

Move the message from this folder to the FOLDER specified.  This will
create a copy (using clone()) first, and flag this original message
to be deleted.  So until the source folder is closed, two copies of
the message stay in memory.  The newly created message (part of the
destination folder) is returned.

=cut

sub moveTo($)
{   my ($self, $folder) = @_;
    my $added = $folder->addMessage($self->clone);
    $self->delete;
    $added;
}

#-------------------------------------------

=head2 The Header

=cut

#-------------------------------------------

sub head(;$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my $new   = shift;
    my $old   = $self->head;
    $self->SUPER::head($new);

    return unless defined $new || defined $old;

    my $folder = $self->folder
        or return $new;

    if(!defined $new && defined $old && !$old->isDelayed)
    {   $folder->messageId($self->messageId, undef);
        $folder->toBeUnthreaded($self);
    }
    elsif(defined $new && !$new->isDelayed)
    {   $folder->messageId($self->messageId, $self);
        $folder->toBeThreaded($self);
    }

    $new || $old;
}

#-------------------------------------------

=head2 Labels

=cut

#-------------------------------------------

=method delete

Flag the message to be deleted.  The real deletion only takes place on
a synchronization of the folder.  See deleted().

The time stamp of the moment of deletion is stored as value.  When the same
message is deleted more than once, the first time stamp will stay.

=examples

 $message->delete;
 $message->deleted(1);  # exactly the same
 delete $message;

=cut

sub delete() { shift->{MBM_deleted} ||= time }

#-------------------------------------------

=method deleted [BOOLEAN]

Set the delete flag for this message.  Without argument, the method returns
the same is the isDeleted() method, which is prefered.  When a true value
is given, delete() is called.

=examples

 $message->deleted(1);          # delete
 $message->delete;              # delete (prefered)

 $message->deleted(0);          # undelete

 if($message->deleted) {...}    # check
 if($message->isDeleted) {...}  # check (prefered)

=cut

sub deleted(;$)
{   my $self = shift;

      ! @_      ? $self->isDeleted   # compat 2.036
    : ! (shift) ? ($self->{MBM_deleted} = undef)
    :             $self->delete;
}

#-------------------------------------------

=method isDeleted

Returns the moment (as the time function returns) when the message was
flagged for deletion, or C<undef> when the message is not deleted.

=examples

 next if $message->isDeleted;

 if(my $when = $message->isDeleted) {
    print scalar localtime $when;
 }

=cut

sub isDeleted() { shift->{MBM_deleted} }

#-------------------------------------------

=head2 Logging and Tracing

=cut

#-------------------------------------------

=method shortString

Convert the message header to a short string, representing the most
important facts (for debugging purposes only).

=cut

sub shortSize(;$)
{   my $self = shift;
    my $size = shift || $self->head->guessBodySize;

      !defined $size     ? '?'
    : $size < 1_000      ? sprintf "%3d "  , $size
    : $size < 10_000     ? sprintf "%3.1fK", $size/1024
    : $size < 100_000    ? sprintf "%3.0fK", $size/1024
    : $size < 1_000_000  ? sprintf "%3.2fM", $size/(1024*1024)
    : $size < 10_000_000 ? sprintf "%3.1fM", $size/(1024*1024)
    :                      sprintf "%3.0fM", $size/(1024*1024);
}

sub shortString()
{   my $self    = shift;
    my $subject = $self->head->get('subject') || '';
    chomp $subject;

    sprintf "%4s(%2d) %-30.30s", $self->shortSize, $subject;
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method readBody PARSER, HEAD [, BODYTYPE]

Read the body of one message.  The PARSER gives access to the folder file.
The HEAD has been read with readHead().  The optional BODYTYPE supplies
the class name of the body to be created, or a code reference to a
routine which can produce a body type based on the head (passed as
first argument).

By default, the BODYTYPE will call Mail::Box::determineBodyType()
where the message will be added to.

=cut

sub readBody($$;$)
{   my ($self, $parser, $head, $getbodytype) = @_;

    unless($getbodytype)
    {   my $folder   = $self->{MBM_folder};
        $getbodytype = sub {$folder->determineBodyType(@_)};
    }

    $self->SUPER::readBody($parser, $head, $getbodytype);
}

#-------------------------------------------

=method diskDelete

Remove a message from disk.  This is not from the folder, but everything
else, like parts of the message which are stored externally from the
folder.

=cut

sub diskDelete() { shift }

#-------------------------------------------

sub forceLoad() {   # compatibility
   my $self = shift;
   $self->loadBody(@_);
   $self;
}

#-------------------------------------------

1;
