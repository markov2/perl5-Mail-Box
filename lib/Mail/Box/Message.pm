
use strict;
use warnings;

package Mail::Box::Message;
use base 'Mail::Message';

use Date::Parse;
use Scalar::Util 'weaken';

=chapter NAME

Mail::Box::Message - manage one message within a mail-folder

=chapter SYNOPSIS

 # Usually these message objects are created indirectly
 use Mail::Box::Manager;
 my $manager = Mail::Box::Manager->new;
 my $folder  = $manager->open(folder => 'Mail/Drafts');
 my $msg     = $folder->message(1);
 $msg->delete;
 $msg->size;   # and much more

=chapter DESCRIPTION

These pages do only describe methods which relate to folders.  If you
access the knowledge of a message, then read M<Mail::Message>.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message's body and head objects may change.

=chapter METHODS

=c_method new OPTIONS

=requires folder FOLDER

The folder where this message appeared in.  The argument is
an instance of (a sub-class of) a M<Mail::Box>.

=option  body_type CODE|CLASS
=default body_type <from folder>

If the body of a message is used delay-loaded, the message must what type
of message to become when it finally gets parsed.  The folder which is
delaying the load must specify the algorithm to determine that type.

=option  size INTEGER
=default size undef

The size of the message, which includes head and body, but without the
message separators which may be used by the folder type.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_body_type}  = $args->{body_type}
        if exists $args->{body_type};

    $self->{MBM_folder}     = $args->{folder};
    weaken($self->{MBM_folder});

    return $self if $self->isDummy;

    $self;
}

#-------------------------------------------

=c_method coerce MESSAGE

Coerce a message to be included in a folder.  The folder itself
is not specified, but the type of the message is transformed correctly.
The coerced version of the message is returned.  When no changes had
to be made, the original message is returned.

=cut

sub coerce($)
{   my ($class, $message) = @_;
    return bless $message, $class
        if $message->isa(__PACKAGE__);

    $class->SUPER::coerce($message);
}

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

=section The message

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
create a copy using M<clone()> first, and flag this original message
to be deleted.  So until the source folder is closed, two copies of
the message stay in memory.  The newly created message (part of the
destination folder) is returned.

=cut

sub moveTo($)
{   my ($self, $folder) = @_;
    my $added = $folder->addMessage($self->clone);
    $self->label(deleted => 1);
    $added;
}

#-------------------------------------------

=section Internals

=method readBody PARSER, HEAD [, BODYTYPE]

Read the body of one message.  The PARSER gives access to the folder file.
The HEAD has been read with M<readHead()>.  The optional BODYTYPE supplies
the class name of the body to be created, or a code reference to a
routine which can produce a body type based on the head (passed as
first argument).

By default, the BODYTYPE will call M<Mail::Box::determineBodyType()>
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
else, like parts of the message which are stored outside from the
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

=section Cleanup

=method destruct

Removes most of the memory occupied by the message by detaching the header
and body.  Then, the object changes into a M<Mail::Box::Message::Destructed>
which will catch all attempts to access the header and body.  Be careful
with the usage of this method.

=cut

sub destruct()
{   require Mail::Box::Message::Destructed;
    Mail::Box::Message::Destructed->coerce(shift);
}

#-------------------------------------------

1;
