
use strict;

package Mail::Box::Message;
use base 'Mail::Message';

use Date::Parse;

our $VERSION = '2.00_02';

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

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE into a Mail::Box::Message.  This
method is automatically called if you add a strange message-type to a
FOLDER.  You usually do not need to call this yourself.

The coerced message is returned on success, else C<undef>.

Example:

   my $folder  = Mail::Box::Mbox->new;
   my $message = Mail::Message->new(...);
   Mail::Box::MBox::Message->coerce($inbox, $message);
   # now $message is a Mail::Box::Mbox::Message

It better to use

   $folder->coerce($message);

which does exacty the same, by calling coerce in the right package.

=cut

sub coerce($$@)
{   my ($class, $folder, $message, %args) = @_;

    # Re-initialize the message, but with the options as specified by the
    # creation of this folder, not the folder where the message came from.

    $args{size} ||= 0;
    $args{folder} = $folder;

    (bless $message, $class)->init(\%args)
        unless $message->isa(__PACKAGE__);

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
    $folder->addMessage($self->clone);
    $self;
}

#-------------------------------------------

sub forceLoad() { shift->loadBody(@_) }   # compatibility

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

This code is beta, version 2.00_02

=cut

1;
