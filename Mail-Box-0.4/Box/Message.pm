
use strict;
use MIME::Entity;
use Mail::Box::Threads;

our $VERSION = 0.4;

=head1 NAME

Mail::Box::Message - Manage one message within a mail-folder

=head1 SYNOPSIS

   use Mail::Box::Message;
   my $folder = new Mail::Box::Message 'text';

=head1 DESCRIPTION

Read Mail::Box::Manager first.  This page also describes
Mail::Box::Message::Runtime, Mail::Box:Message::Dummy,
Mail::Box::Message::NotParsed, and Mail::Box::Message::NotReadHead.

=head2 Extending MIME::Entity

Because reading MIME::Entity objects from file is quite time-consuming
and memory flooding, this module actively tries to keep most messages
in the folder-files where they are stored in un-parsed form.  When a folder
is opened, only some of the header-lines of the messages are taken and
stored in objects.  Not before the message is seriously used, the
message is translated into a real MIME::Entity.

=head2 Delayed loading of messages

When a folder is read, the C<lazy_extract> option to C<Mail::Box::new>
determines if the content of the message is to be parsed immediately into
a Mail::Box::Message or should be left unparsed in the folder-file.  In
the latter case, a Mail::Box::Message::NotParsed is created.

Not-parsing messages improves the speed of folder reading, and reduce
the memory footprint of your program considerably.  However, it keeps
the folder-file locked, so should not be used on the incoming messages
mail-box.

The parsing of a message (reading the non-parsed messages from the
folder file and translating it into Mail::Box::Message type objects)
is automatically triggered when you access head-lines which were not
specified in C<take_headers> when the folder was read, and when you
call methods which are not defined on a non-parsed message.

=head2 Classes defined in the module

This page handles three types of messages:

=over 4

=item * Mail::Box::Message

A read message.  This is a full decendent of MIME::Entity, with all
information on the message and its parts stored in easily and fast
accessible memory-structures.

=item * Mail::Box::Message::Dummy

A message which is a place-holder in a thread description.  Because
folders are an (organized) mess of messages, the order in which
thread-elements are discovered may vary.

When a thread is discovered (a message contains C<In-Reply-To> or
C<References> fields) this object-type is used to fill holes in
the linked list of thread messages.  See Mail::Box::Threads.

=item * Mail::Box::Message::NotParsed

This is a nearly ready-to-go message.  When scanning a folder, the
C<lazy_extract> parameter of C<Mail::Box::new> determines which
messages are directly parsed into a Mail::Box::Message, and which
are not yet parsed.

Messages which are not directly parsed into a real message object are
stored as an Mail::Box::Message::NotParsed object.  This
object only contains a few important header-lines, and triggers to
load the message for real on the moment other information on this
message is needed.

Which header-lines are taken is determined by the C<take_headers>
parameter of C<Mail::Box::new>.  Taking too few headers for your
task will result in bad performance: all message will be read.
When you take too many headers, this is bad for the memory usage of
your program.

=back

Two more classes are defined, to help the message-types to function
properly:

=over 4

=item * Mail::Box::Message::Runtime

Data and functionality which is not stored in the folder, but is shared
by various message-types (a real-message, a dummy, and a not-parsed)

=item * Mail::Box::Message::NotReadHead

A header which is part of a Mail::Box::Message::NotParsed.  It contains
some header-lines, but far from all.  It can trigger the not-parsed
to load itself from the folder.

=back

=head2 State transition

Messages are detected when reading a folder, or composed by the user when
it is sent by a used.  The relationships shown below are only about reading
existing folders.

                  unknown references
   Mail::Box      and reply-to's        Mail::Box
   finds message ---------------------> ::Message::Dummy
         |                                    |
         v messages                           |
         |                                    |
         |                                    |
        / \was dummy                          |
        |  '--------------> merge <-----------'
        |                     |
        |                     |
        \new                  |
         `-->-----,  ,-----<--'
                  lazy
                extract?
             yes/       \no
               /         `--->-------,
              v                       |
        Mail::Box                     |
        ::Message::NotParsed          |
              |                       v
              |serious use         Mail::Box
               `---------------->-- ::Message

=head2 Class structure for messages

As example, the next scheme uses Mbox, however there are more
parallel extentions of Mail::Box::Message (in the future).

     ::Message::Mbox             ::Message::Mbox
          |     \                  / ::NotParsed
          |      \                /         |
          |       \              /          |
          |        ::Message::Mbox          |
          |              ::Runtime          |
          |                                 |
          v                                 v
     ::Message         ::Dummy          ::Message
          |   \           |           ::NotParsed
          |    \          |           /
          |     \         v          /
          |       ::Message::Runtime
          v
     MIME::Entity
          |
          |
          v
     Mail::Internet

The rest of this manual-page describes the functionalities of each
single class.

=cut

###
### Mail::Box::Message::Runtime
###

package Mail::Box::Message::Runtime;

=head1 Mail::Box::Message::Runtime

This class is a base for all kinds of messages.  It defines the simularities
between messages in various stages: dummy, not-parsed, or parsed.

=over 4

=cut


#-------------------------------------------

=item new ARGS

Initialize the runtime variables of a message.  The following options
are supported:

=over 4

=item * folder => FOLDER

(obligatory) The folder where this message appeared in.  The argument is
an instance of (a sub-class of) a Mail::Box.

=item * size => INTEGER

The size of the message inclusive headers and accompanying lines (such
as the `From' line in mboxes) in bytes.

=item * messageID => STRING

The id on which this message can be recognized.  If none specified, there
will be one assigned to the message to be able to pass unique
message-ids between objects.

=item * modified => BOOL

Whether there are some modifications to the message from the start-on.
For instance, new message will be flagged modified immediately.

=item * deleted => BOOL

Is the file deleted from the start?

=item * labels => [ STRING => VALUE, ... ]

Set the specified labels to their accompanying value.  In most cases, this
value will only be used as boolean, but it might be more complex.

=back

=cut

sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

my $unreg_msgid = time;

sub init($)
{   my ($self, $args) = @_;

    unless(exists $args->{messageID})
    {   my $msgid = $self->head->get('message-id');
        $args->{messageID} = $1 if $msgid && $msgid =~ m/\<(.*?)\>/;
    }

    $self->{MBM_size}      = $args->{size}      || 0;
    $self->{MBM_messageID} = $args->{messageID} || $unreg_msgid++;
    $self->{MBM_deleted}   = $args->{deleted}   || 0;
    $self->{MBM_modified}  = $args->{modified}  || 0;
    $self->folder($args->{folder}) if $args->{folder};

    unless($self->isDummy)
    {   $self->{MBM_labels}    = { seen => 0 };
        $self->setLabel(@{$args->{labels}}) if $args->{labels};
    }

    $self;
}

#-------------------------------------------

=item messageID

Retreive the message's id.  Every message has a unique message-id.  This id
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

=item isParsed

C<isParsed> checks whether the message is parsed (read from file).  Returns
true or false.  Only a Mail::Box::Message will return true.

=cut

sub isParsed() { 0 }


#-------------------------------------------

=item isDummy

C<isDummy> Checks whether the message is only found in a thread, but
not (yet) in the folder.  Only a Mail::Box::Message::Dummy will
return true.

=cut

sub isDummy() { 0 }

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

iExamples:
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
{   my Mail::Box::Message $self    = shift;
    return $self->{MBM_deleted} unless @_;

    my $delete = shift;
    return $delete if $delete==$self->{MBM_deleted};

    my $folder = $self->folder;
    $folder->modifications($delete ? 1 : -1);
    $folder->messageDeleted($self, $delete);

    $self->{MBM_deleted} = ($delete ? time : 0);
}

#-------------------------------------------

=back

=head2 Label management

Labels are used to store knowledge about handling of the message within
the folder.  Flags about whether a message was read, replied to, or
(in some cases) scheduled for deletion.

=over 4

=item setLabel LIST

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

sub label(@) { wantarray ? @{shift->labels}{@_} : shift->labels->{$_[0]} }

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
    my $status = $self->head->get('status') || return ();

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
    my $status = $self->head->get('x-status') || return ();

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

=back

=head2 Thread management

=over 4

=item references

=item in-reply-to

Retreive what the message says is the discussion thread it is in.  This
is an ordered list of message-ids.

Examples:
   my @ref_ids = $message->references;
   my $nesting = $message->references;
   my @replies = $message->in_reply_to;

=cut

sub references()
{   my Mail::Box::Message $self    = shift;
    my $refs = $self->head->get('references') || return ();
    $refs =~ m/\<(.*?)\>/g;
}

sub in_reply_to()
{   my Mail::Box::Message $self = shift;
    my $reply = $self->head->get('in-reply-to') || return;
    ($reply =~ m/\<(.*?)\>/)[0];
}

#-------------------------------------------

=item shortString

Convert the message header to a short string, representing the most
important facts (for debugging purposes only).

=cut

sub shortSize($)
{   my $self = shift;
    my $size = shift;
      !defined $size     ? '?'
    : $size < 1_000      ? "$size "
    : $size < 10_000     ? sprintf "%3.1fK", $size/1024
    : $size < 100_000    ? sprintf "%3.0fK", $size/1024
    : $size < 1_000_000  ? sprintf "%3.2fM", $size/1024
    : $size < 10_000_000 ? sprintf "%3.1fM", $size/1024
    :                      sprintf "%3.0fM", $size/(1024*1024);
}

sub shortString()
{   my $self    = shift;
    my $subject = $self->head->get('subject') || '';
    chomp $subject;

    sprintf "%4s(%2d) %-30.30s"
          , $self->shortSize($self->{MBM_size})
          , scalar $self->followUps, $subject;
}

###
### Mail::Box::Message
###

package Mail::Box::Message;
use Carp;
our @ISA = ( 'Mail::Box::Message::Runtime'
           , 'Mail::Box::Thread'
           , 'MIME::Entity'
           );

#-------------------------------------------

=back

=head1 Mail::Box::Message

This object extends a MIME::Entity.  This is the only object type defined
in this set of packages which represents a real message (which parsed into
memory, with access to all headers, and writeable)

=head2 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new LINES [, OPTIONS]

Create a new message.  LINES is a reference to an array of lines which
describe the message, or a file-handle.  The options is a list of
labeled values.  Extentions (sub-classes) of an Mail::Box::Message
may define more options, but these are general:

=over 4

=back

=cut

# Until the MIME::Entity split-up its new into new+init, we have to
# implement an new/init which takes a MIME::Entity, then copies all data
# into our own structure.

sub new(@)
{   my $class = shift;
    $class->Mail::Box::Message::Runtime::new(@_);
}

sub init($)
{   my ($self, $args) = @_;
    $self->delayedInit($args) || return $self;

    $self->Mail::Box::Message::Runtime::init($args);
    $self->Mail::Box::Thread::init($args);
}

sub delayedInit($)
{   my ($self, $args) = @_;

    # When MIME::Entity gets a init() once...
    # Now we have to copy things...

    my $message = $args->{message} || return $self;
    @$self{ keys %$message } = values %$message;

    $self;
}

sub isParsed() { 1 }

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
to get a list of Mail::Box::Message objects, each representing one
part of the message.  Be warned that even such part can be split in
nested parts.  You can pass an array-reference with messages to set a
new list of parts.

See L</body> and L</bodyhandle> above.

=cut

sub parts(@) 
{   my $self = shift;

    # Upgrade the parts to this extended object class.
    my $parts = 0;
    map {$self->part_upgrade($_, $parts++)}
       $self->MIME::Entity::parts( [@_] );
}

sub part_upgrade($$)   # from MIME::Entity into Mail::Box::Message
{   my ($self, $part, $count) = @_;

    $part->Mail::Box::Message::Runtime::init
      ( messageID => $self->messageID . '-p$count'
      );

    $part->{MBM_is_part} = 1;

#   bless $part, ref $self;    # shouldn't be necessary
    $self;
}
 
#-------------------------------------------

=item removePart PART|INDEX

Remove one part of the list of parts from this message.  Specify a PART
(Mail::Box::Message instance) or an index (sequence-number is list of
parts)

=cut

sub removePart($)
{   my ($self, $part) = @_;
    my @parts = $self->parts;

    $self->parts
      ( ref $part
      ? grep({$part->messageID ne $_->messageID} @parts)
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
### Mail::Box::Message::Dummy
###

package Mail::Box::Message::Dummy;
our @ISA = ( 'Mail::Box::Message::Runtime'
           , 'Mail::Box::Thread'
           );

#-------------------------------------------

=back

=head1 Mail::Box::Message::Dummy

A dummy message is a placeholder, for instance for messages in threads
which are found in a reference-list, but not (yet) in the folder.

=over 4

=cut

#-------------------------------------------

=item new MESSAGE-ID

(Class method)  Create a new dummy message.

Examples:
    my $message = Mail::Box::Message::Dummy->new($id);
    if($message->isDummy) {...}

=cut

sub new($) { shift->SUPER::new(messageID => shift, deleted => 1) }
 
sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Message::Runtime::init($args);
    $self->Mail::Box::Thread::init($args);
}

sub isDummy() { 1 }

sub shortSize($) {"   0"};

sub shortString()
{   my Mail::Box::Message $self = shift;
    sprintf "----(%2d) <not found>"
          , scalar $self->followUps;
}


###
### Mail::Box::Message::NotParsed
###

package Mail::Box::Message::NotParsed;
our @ISA = ( 'Mail::Box::Message::Runtime'
           , 'Mail::Box::Thread'
           );

#-------------------------------------------

=back

=head1 Mail::Box::Message::NotParsed

A message where most of the data still resides in the folder-file, is a
'message which is not read' (yet).  This status is signalled by the
type of the object.

=head2 PUBLIC INTERFACE

=cut

#-------------------------------------------

=item new ARGS

Create a not parsed message.  The message can have a C<not-read-head>,
which means that only a few of the header-lines are kept, or a
real MIME::Head to start with.

=cut

sub init($)
{   my ($self, $args) = @_;

    my $head = $self->{MBM_head} = $args->{head};
    $head->message($self) if $head->can('message');

    $self->Mail::Box::Message::Runtime::init($args);
    $self->Mail::Box::Thread::init($args);
    $self;
}

sub DESTROY()
{   delete shift->{MBM_head};     # remove two-way reference.
}

#-------------------------------------------

=item AUTOLOAD

When any method is called which can not be performed without parsing
the whole folder message, Perl calls the autoloader.  A check is performed
to see if not anyone has accidentally an old message-handle: we may
otherwise read the message twice.

=cut

our $AUTOLOAD;

sub AUTOLOAD
{   my $self   = $_[0];

#warn "Autoload on message $AUTOLOAD.\n";
    # Try to avoid double reading caused by old handles to the un-parsed
    # message info.

    my $folder = $self->folder;
    my $public = $folder->messageWithId($self->messageID);
    if($public->isParsed)
    {   # autoload message which is already parsed, but caller
        # does not have the right handle yet.
        $_[0] = $public;
    }
    else
    {   # Autoloading is still required.
        $_[0] = $public = $self->load($folder->{MB_message_type});
        $folder->messageWithId($self->messageID, $public);
    }

    (my $call = $AUTOLOAD)
        =~ s/$folder->{MB_notparsed_type}/$folder->{MB_message_type}/;

    shift;
    no strict 'refs';
#   goto $public->$call(@_);
    $public->$call(@_);
}

#-------------------------------------------

=item head

This function returns a Mail::Box::Message::NotReadHead object on
which you may perform any actions as expected from MIME::Header object.
Performing actions on a header which is part of a non-parsed message
is complicated by the fact that we have some header-lines, but not all.

See L</Mail::Box::Message::NotReadHead> below.

=cut

sub head() { shift->{MBM_head} }

###
### Mail::Box::Message::NotReadHead
###

package Mail::Box::Message::NotReadHead;

our $AUTOLOAD;

#-------------------------------------------

=head1 Mail::Box::Message::NotReadHead

This object contains a few header-lines which were captured during the
initial reading of the folder.  It will also automagically load the messages on
any other call to C<head>.

=head2 PUBLIC INTERFACE

See MIME::Header for all methods you can perform on this object.  The
following methods need extra consideration.

=over 4

=item new ARGS

(Class method)  Called by the Mail::Box::Message::NotParsed method
C<new> to store some header-lines which were capurtured during the
initial reading through the folder file.  See the C<take_headers>
option on how to add header-lines to this structure.

The following parameters can be passed to new:

=over 4

=item * expect FIELDNAMES

(obligatory) Which fields will be taken from the folder-file.  Even when we
do not actually find all these fields, we still have to know when the message
lacks the field, to avoid that the message is read from the folder
to find-out that the line isn't there either.

=back

=cut

sub new(@) { (bless {}, shift)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{MBM_expect}  = $args->{expect};
    $self->{MBM_message} = $args->{message};
    $self;
}

#-------------------------------------------

=item get TAG [, INDEX]

=item get_all TAG

=item count TAG

Overruled methods, which first check if we know about the header.  In
case we do, the values can be returned immediately.  Otherwise we trigger
the message to be read from the folder-file and then retry on the
real Mail::Box::Message object.

=cut

sub get($;$)
{   my ($self, $tag, $index) = (shift, lc(shift), shift);

    if(not exists $self->{$tag})
    {   # Tag not found.

        # Check whether we were looking for this field when we scanned
        # the folder.  If so, we do not need to parse the message.
        foreach (@{$self->{MBM_expect}})
        {   return undef if $tag =~ m/^$_$/;
        }

        # The header-line was not captured, so we need to load the
        # whole message to look for the field.
        $AUTOLOAD = (ref $self).'::get';
        goto $self->AUTOLOAD($tag, $index);
    }
    elsif(ref $self->{$tag})
    {   return wantarray && !defined $index
             ? @{$self->{$tag}}
             : $self->{$tag}[$index||0];
    }
    else
    {   return $index ? undef : $self->{$tag};
    }
}
        
sub get_all($) { my @get = shift->get(shift)  } # force list context
sub count($)   { scalar shift->get_all(shift) }

#-------------------------------------------

=item setField NAME, CONTENT

Store a content into a field.  Do only specify fields which are defined
with C<expect> when this object was instantiated.

You may add the same name more than once.  In
that case, the C<get> method in list context (and the C<get_all> method)
will return all definition in the order that they were added.  For the
C<Received:> field in messages, that means that the most recently added
line to the message is put first in the list (they are in reverse order
in the mime-header.

=cut

sub setField($$)
{   my $self    = shift;
    my $field   = lc (shift);
    my $content = shift;

    if(!defined $self->{$field}) { $self->{$field} = $content }
    elsif(ref($self->{$field}))  { push @{$self->{$field}}, $content }
    else { $self->{$field} = [ $self->{$field}, $content ] }
}

#-------------------------------------------

=item message [MESSAGE]

Get (or check) the message to which this header belongs.

=cut

sub message(;$)
{   my $self = shift;
    @_ ? $self->{MBM_message} = shift : $self->{MBM_message};
}

#-------------------------------------------

=item AUTOLOAD

Load the message, then capture the real header, and finally calls the
method on the what should have been called in the first place.

Example:
    $message->head->get('some-field')

where $message is a C<Mail::Box::Message::NotParsed>, will return a
C<Mail::Box::Message::NotReadHead> from its C<head> call.  A get of
a previously captured header returns the right value, however in case
not, the following steps are taken:

=over 4

=item *

C<get> calls C<AUTOLOAD> to get a new header.

=item *

C<NotReadHead::AUTOLOAD> will call C<NotParsed::AUTOLOAD> to read the
message.

=item *

C<NotParsed::AUTOLOAD> reads the message from the folder and returns it
to the header autoloader.

=item *

The header autoloader calls the real C<get> method of the
C<Mail::Box::Message>, as autoloaders should do.

=back

=cut

sub AUTOLOAD
{   my $self = $_[0];
    (my $method = $AUTOLOAD) =~ s/.*\:\://;

#warn "Load!! for $AUTOLOAD\n";
    my $head = $self->{MBM_message}->load->head;

    $_[0]    = $head;   # try to infuence the handle which the caller
                        # has in its hands.
    shift;              # Now caller know of change.

    no strict 'refs';
    $head->$method(@_);
}

sub DESTROY { shift }

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.4

=cut

1;
