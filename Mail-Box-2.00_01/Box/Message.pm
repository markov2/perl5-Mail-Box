
use strict;

package Mail::Box::Message;
use base 'Mail::Message';

use Date::Parse;

our $VERSION = '2.00_01';

=head1 NAME

Mail::Box::Message - Manage one message within a mail-folder

=head1 SYNOPSIS

   # Usually these message objects are created indirectly
   use Mail::Box::Manager;
   my $manager = Mail::Box::Manager->new;
   my $folder  = $manager->open(folder => 'Mail/Drafts');
   my $msg     = $folder->message(1);
   $msg->delete;
   $msg->size;   # and much more

=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.
These pages do only describe methods which relate to folders.  If you
access the knowledge of a message, then read C<Mail::Message>.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message's body and head objects may change.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.


=head1 METHODS

=over 4

=cut


#-------------------------------------------

=item new ARGS

Initialize the runtime variables of a message.  The following options
are supported:

 body              Mail::Message             undef
 deleted           Mail::Box::Message        0
 folder            Mail::Box::Message        <required>
 head              Mail::Message             undef
 labels            Mail::Box::Message        []
 log               Mail::Reporter            'WARNINGS'
 messageID         Mail::Box::Message        undef
 modified          Mail::Box::Message        0
 size              Mail::Box::Message        undef
 trace             Mail::Reporter           'WARNINGS'

=over 4

=item * folder =E<gt> FOLDER

(obligatory) The folder where this message appeared in.  The argument is
an instance of (a sub-class of) a Mail::Box.

=item * size =E<gt> INTEGER

The size of the message inclusive headers and accompanying lines (such
as the `From' line in mboxes) in bytes.

=item * messageID =E<gt> STRING

The id on which this message can be recognized.  If none specified, there
will be one assigned to the message to be able to pass unique
message-ids between objects.

=item * modified =E<gt> BOOL

Whether there are some modifications to the message from the start-on.
For instance, new message will be flagged modified immediately.

=item * deleted =E<gt> BOOL

Is the file deleted from the start?

=item * labels =E<gt> [ STRING =E<gt> VALUE, ... ]

Set the specified labels to their accompanying value.  In most cases, this
value will only be used as boolean, but it might be more complex.

=back

=cut

my $unreg_msgid = time;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_size}       = $args->{size}      || 0;
    $self->{MBM_deleted}    = $args->{deleted}   || 0;
    $self->{MBM_modified}   = $args->{modified}  || 0;
    $self->{MBM_messageID}  = $args->{messageID}
        if exists $args->{messageID};

    $self->{MBM_labels}   ||= {};
    $self->folder($args->{folder}) if $args->{folder};

    return $self if $self->isDummy;

    $self->{MBM_labels} =
      { seen => 0
      , ($args->{labels} ? @{$args->{labels}} : ())
      };

    $self;
}

#-------------------------------------------

=item messageID

Retrieve the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

sub messageID() { shift->{MBM_messageID} }

#-------------------------------------------

=item folder [FOLDER]

In with folder did we detect this message/dummy?  This is a reference
to the folder-object.

=cut

sub folder(;$)
{   my $self = shift;
    @_ ? ($self->{MBM_folder} = shift) : $self->{MBM_folder};
}

#-------------------------------------------

=item size

Returns the size of the message, including headers.

Example:

    print $folder->message(8)->size;

=cut

sub size() { shift->{MBM_size} }

#-------------------------------------------

=item modified [BOOL]

Check (or set, when an argument is supplied) that the message-contents has
been changed by the program.  This is used later, when the messages are
written back to file.

Examples:

    if($message->modified) {...}
    $message->modified(1);

=cut

sub modified(;$)
{   my $self = shift;

    return $self->{MBM_modified} unless @_;

    my $change = shift;
    $self->folder->modifications($change - $self->{MBM_modified});
    $self->{MBM_modified} = $change;
}

#-------------------------------------------

=item delete

Flag the message to be deleted.  The real deletion only takes place on
a synchronization of the folder.

Examples:

   $message->delete;
   delete $message;

=cut

sub delete() { shift->deleted(1) }

#-------------------------------------------

=item deleted [BOOL]

Check or set the deleted flag for this message.  This method returns
undef (not deleted, false) or the time of deletion (true).  With a
BOOL argument, the status is changed first.

Examples:

   if($message->deleted) {...}
   $message->deleted(0);        # undelete

=cut

sub deleted(;$)
{   my $self = shift;
    return $self->{MBM_deleted} unless @_;

    my $delete = shift;
    return $delete if $delete==$self->{MBM_deleted};

    my $folder = $self->folder;
    $folder->modifications($delete ? 1 : -1);
    $folder->messageDeleted($self, $delete);

    $self->{MBM_deleted} = ($delete ? time : 0);
}

#-------------------------------------------

=item seqnr [INTEGER]

Get (add set) the number of this message is the current folder.

=cut

sub seqnr(;$)
{   my $self = shift;
    @_ ? $self->{MBM_seqnr} = shift : $self->{MBM_seqnr};
}

#-------------------------------------------

=item timestamp

Returns an indication on the moment that the message was originally
sent.  The exact value which is returned is operating-system dependent,
but on UNIX systems will be in seconds since 1 January 1970.

=cut

sub MIME::Entity::timestamp()
{   my $self = shift;
    my $head = $self->head || return;
    return $self->{MBM_timestamp} if $self->{MBM_timestamp};

    if(my $date = $self->head->get('date'))
    {   my $stamp = str2time($date, 'GMT');
        return $self->{MBM_timestamp} = $stamp if $stamp;
    }

    foreach ($self->head->get('received'))
    {   my $stamp = str2time($_, 'GMT');
        return $self->{MBM_timestamp} = $stamp if $stamp;
    }

    undef;
}

#-------------------------------------------

=back

=head2 Label management

Labels are used to store knowledge about handling of the message within
the folder.  Flags about whether a message was read, replied to, or
(in some cases) scheduled for deletion.

=over 4

=item setLabel LIST

The LIST is a set of scalars forming key,value pairs.

=cut

sub setLabel(@)
{   my $self   = shift;
    my $labels = $self->labels;
    while(@_)
    {   my $key = shift;          # order of two shifts in one line is not
        $labels->{$key} = shift;  # defined.
    }
    $self;
}

#-------------------------------------------

=item label STRING [ ,STRING ,...]

Get the value related to the label(s).  This returns a list of values, which
may be empty, undefined, or a value which evaluates to TRUE.

Example:

    if($message->label('seen')) {...}
    my ($seen, $current) = $msg->label('seen', 'current');

=cut

sub label(@)
{  my $self = shift;
   wantarray
   ? @{$self->{MBM_labels}}{@_}
   : $self->{MBM_labels}{(shift)};
}

#-------------------------------------------

=item labels

Returns all known labels.  In SCALAR context, it returns the knowledge
as reference to a hash.  This is a reference to the original data, but
you shall *not* change that data directly: call C<setLabel()> for
changes!

In LIST context, you get a list of names which are defined.  Be warned
that they will not all evaluate to true, although most of them will.

=cut

sub labels()
{   my $self = shift;
    wantarray ? keys %{$self->{MBM_labels}} : $self->{MBM_labels};
}

sub statusToLabels()
{   my $self   = shift;
    my $status = $self->head->get('status') || return $self;

    $self->setLabel( seen => $status =~ /R/
                   , old  => $status =~ /O/
                   );
}

sub createStatus()
{   my $self   = shift;
    my ($seen, $old) = $self->labels('seen', 'old');

    $self->head->replace
      ( 'Status', ($seen ? 'RO' : $old ? '0' : ''));

    $self;
}

sub XstatusToLabels()
{   my $self   = shift;
    my $status = $self->head->get('x-status') || return $self;

    $self->setLabel( replied => $status =~ /A/
                   , flagged => $status =~ /F/
                   );
}

sub createXStatus()
{   my $self   = shift;
    my ($replied, $flagged) = $self->labels('replied', 'flagged');

    $self->head->replace
      ( 'X-Status', ($replied ? 'A' : '').($flagged ? 'F' : ''));

    $self;
}

#-------------------------------------------

=item shortString

Convert the message header to a short string, representing the most
important facts (for debugging purposes only).

=cut

sub shortSize(;$)
{   my $self = shift;
    my $size = shift || $self->{MBM_size};

      !defined $size     ? '?'
    : $size < 1_000      ? "$size "
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

=item diskDelete

Remove a message from disk.  This is not from the folder, but everything
else, like parts of the message which are stored externally from the
folder.

=cut

sub diskDelete() { shift }

###
### Mail::Box::Message::Parsed
###

package Mail::Box::Message::Parsed;
use vars qw/@ISA/;
use MIME::Entity;
use IO::Scalar;

@ISA = ( 'Mail::Box::Message', 'MIME::Entity');

#-------------------------------------------

=back

=head1 CLASS Mail::Box::Message::Parsed

This object extends a MIME::Entity.  This is the only object type defined
in this set of packages which represents a real message (which parsed into
memory, with access to all headers, and writeable)

=head2 METHODS

=over 4

=cut

#-------------------------------------------

=item new [OPTIONS]

Create a new message.  The options available are taken from
C<Mail::Box::Message::new()>, as described above.

If you want to add a message to a folder, which is derived
from some strange source, then you do:

     use MIME::Parser;
     my $parser = MIME::Parser->new;
     my $entity = $parser->parse(@lines);
     $folder->addMessage($entity);

The C<addMessage()> accepts anything what is based on Mail::Internet.

=cut

# Until the MIME::Entity split-up its new into new+init, we have to
# implement an new/init which takes a MIME::Entity, then copies all data
# into our own structure.

sub new(@)
{   my $class = shift;
    $class->Mail::Box::Message::new(@_);
}

sub init($)
{   my ($self, $args) = @_;
    $self->delayedInit($args) || return $self;

    $self->Mail::Box::Message::init($args);
}

sub delayedInit($)
{   my ($self, $args) = @_;

    # When MIME::Entity gets a init() once...
    # Now we have to copy things...

    my $message = $args->{message} || return $self;
    @$self{ keys %$message } = values %$message;
    $self->head->unfold;

    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE into a Mail::Box::Message::Parsed.  This
method is automatically called if you add a strange message-type to a
FOLDER.  You usually do not need to call this yourself.

The coerced message is returned on success, else C<undef>.

Example:

   my $folder = Mail::Box::Mbox->new;
   my $entity = MIME::Entity->new(...);
   Mail::Box::MBox::Message::Parsed->coerce($inbox, $entity);
   # now $entity is a Mail::Box::Mbox::Message::Parsed

It better to use

   $folder->coerce($entity);

which does exacty the same, by calling coerce in the right package.

=cut

sub coerce($$@)
{   my ($class, $folder, $message, %args) = @_;

    # If we get the primitive Mail::Internet type, then we first upgrade
    # into a MIME::Entity.  It is disappointing that that class does not
    # have an init() method.  I need to copy some code from the instance
    # method (new) for MIME::Entity.  Hope that never changes...

    if(ref $message eq 'Mail::Internet')
    {   $message->{ME_Parts} = [];                 # stolen code.
    }

    # Re-initialize the message, but with the options as specified by the
    # creation of this folder, not the folder where the message came from.

    $args{size} ||= 0;          # not available for MIME::Entities
    $args{folder} = $folder;
    unless ($message->isa(__PACKAGE__))
    {   (bless $message, $class)->init(\%args);
    }

    # Now also coerce the parts of the message into a Mail::Box::Message.
    # Parts are not folder specific.

    foreach my $part (@{$message->{ME_parts}})
    {   __PACKAGE__->coerce($folder, $part, %args);
    }

    $class;
}

#-------------------------------------------

=item copyTo FOLDER

Copy the message to the indicated opened FOLDER, without deleting the
original.

Example:

   my $draft = $mgr->open(folder => 'Draft');
   $message->copyTo($draft);

=cut

sub copyTo($)
{   my ($self, $folder) = @_;

    # To create a copy, we print to file and then parse it back.  This
    # is a real trick which could consume inefficient amounts of memory
    # and time, but is independent from the MIME::Entity implementation.

    my $internal;
    my $plaintext = new IO::Scalar;
    $plaintext->open(\$internal);
    $self->print($plaintext);

    my $parser    = $folder->parser;
    $folder->addMessage($parser->parse_data($internal));

    $self;
}

#-------------------------------------------

=item forceLoad

This method is called to signal that the message must be loaded, although
the method only returns the folder.

=cut

sub forceLoad() { shift }

#-------------------------------------------

=item body

Call C<body> to get the whole message-body in storable message format
(multiparts are folded back into one message).  This may be useful to
print the whole message.  If you want to access the message content, you
should used L</bodyhandle> or L</parts> which are described below.

=cut

# Just to help understanding what is happening, but this method is
# inherited.

#-------------------------------------------

=item bodyhandle

Some messages are multi-parts, other are plain.  Check which type of message
you have (with C<is_multipart> as described in MIME::Entity) before accessing
its content.

If the parsing of the folder was delayed (controlled by the `lazy_extract'
option at folder-creation) this implies that the message-body is read
from folder and parsed.  This is performed automatically.

If you do not have a multipart message, you call C<bodyhandle>, which
returns a handle to a handle-type object which can be opened to read
the body of the message.

Example:

    sub print_body($)
    {   my ($self,$message) = @_;
        if($message->is_multipart)
             { $self->print_body($_)
                   foreach $message->parts }
        else { $message->bodyhandle->print }
    }

=cut

#-------------------------------------------

=item parts [ARRAY]

Some messages are multi-parts, other are plain.  Check which type of message
you have (with C<is_multipart> as described in MIME::Entity) before accessing
its content.

If the parsing of the folder was delayed (controlled by the `lazy_extract'
option at folder-creation) this implies that the message-body is read
from folder and parsed.  This is performed automatically.

When you do have a multipart message, you have to call C<parts>
to get a list of Mail::Box::Message::Parsed objects, each representing one
part of the message.  Be warned that even such part can be split in
nested parts.  You can pass an array-reference with messages to set a
new list of parts.

See L</body> and L</bodyhandle> above.

=cut

my $partcount;
sub part_upgrade($$)   # from MIME::Entity into Mail::Box::Message::Parsed
{   my ($self, $part) = @_;

    bless $part, ref $self;
    $part->Mail::Box::Message::Parsed::init
      ( { messageID => $self->messageID . '-p$partcount' }
      );

    $part->{MBM_is_part} = 1;
    $self;
}
 
#-------------------------------------------

=item removePart PART|INDEX

Remove one part of the list of parts from this message.  Specify a PART
(Mail::Box::Message::Parsed instance) or an index (sequence-number is
list of parts)

=cut

sub removePart($)
{   my ($self, $part) = @_;
    my @parts = $self->parts;

    $self->parts
      ( ref $part
      ? grep {$part->messageID ne $_->messageID} @parts
      : splice(@parts, $part, 1)
      );
}

#-------------------------------------------

=item isPart

A part of a message is of the same type as the message itself.  This call
can distinguish between the two.

=cut

sub isPart() { shift->{MBM_is_part} || 0 }


###
### Mail::Box::Message::NotParsed
###

package Mail::Box::Message::NotParsed;
use vars qw/@ISA $AUTOLOAD/;
@ISA = 'Mail::Box::Message';

#-------------------------------------------

=back

=head1 Mail::Box::Message::NotParsed

A message where most of the data still resides in the folder-file, is a
'message which is not read' (yet).  This status is signalled by the
type of the object.

=head2 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a not-parsed message.  The message can have a C<not-read-head>,
which means that only a few of the header-lines are kept, or a
real MIME::Head to start with.

=cut

sub init($)
{   my ($self, $args) = @_;

    if(my $head = $args->{head})
    {   $self->{MBM_head} = $head;
        $head->message($self) if $head->can('message');
    }

    $self->SUPER::init($args);
    $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head2 Class structure for messages

As example, the next scheme uses the fake folder-type C<XYZ>, which
may be for instance C<Mbox> or C<MH>.  

    Mail::Box::XYZ::Message
               ^
               |
       Mail::Box::Message
               ^
               |
         Mail::Message
         ::Body ::Head

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_01

=cut

1;
