use strict;
use warnings;

package Mail::Message::Part;
use base 'Mail::Message';

use Carp;

=head1 NAME

Mail::Message::Part - a part of a message, but a message by itself.

=head1 SYNOPSIS

 my Mail::Message $message = ...;
 if($message->isMultipart) {
    my Mail::Message::Part $part;

    foreach $part ($message->body->parts) {
       $part->print(\*OUT);
       my $attached_head = $part->head;
       my $attached_body = $part->body;      # encoded as read
       my $attached_body = $part->decoded;   # transfer-encoding removed
    }
 }

=head1 DESCRIPTION

A Mail::Message::Part object contains a message which is included in
the body of an other message.  For instance I<attachments> are I<parts>.

READ Mail::Message FIRST.  A part is a special message: it has a
reference to its parent message, and will usually not be sub-classed
into mail-folder-specific variants.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

Create a message part.

=option  container BODY
=default container <obligatory>

Reference to the parental Mail::Message::Body object where this
part is a member of.  That object may be a Mail::Message::Body::Multipart
or a Mail::Message::Body::Nested.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    confess "No container specified for part.\n"
        unless exists $args->{container};

    $self->{MMP_container} = $args->{container};
    $self;
}

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=c_method buildFromBody BODY, CONTAINER, HEADERS

Shape a message part around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.
Next to that, more HEADERS can be specified.  No headers are obligatory.
No extra headers are fabricated automatically.

=example

 my $multi = Mail::Message::Body::Multipart->new;
 my $part  = Mail::Message::Part->buildFromBody($body, $multi);

=cut

sub buildFromBody($$;@)
{   my ($class, $body, $container) = (shift, shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $part = $class->new
     ( head      => $head
     , container => $container
     , @log
     );

    $part->body($body);
    $part;
}

#------------------------------------------

=method coerce BODY|MESSAGE, MULTIPART, HEADERS

Transforms a BODY or MESSAGE to a real message part.  The MULTIPART refers
to the parental body.

When ta BODY is specified, extra HEADERS can be supplied as well.  Bodies
are coerced into message parts by calling buildFromBody().  If you specify
a MESSAGE residing in a folder, this message will automatically be cloned.

=cut

sub coerce($@)
{   my ($class, $thing, $container) = (shift, shift, shift);

    return $class->buildFromBody($thing, $container, @_)
        if $thing->isa('Mail::Message::Body');

    # Although cloning is a Bad Thing(tm), we must avoid modifying
    # header fields of messages which reside in a folder.
    my $message = $thing->isa('Mail::Box::Message') ? $thing->clone : $thing;

    my $part    = $class->SUPER::coerce($message);
    $part->{MMP_container} = $container;
    $part;
}

#------------------------------------------

=head2 The Message

=cut

#------------------------------------------

=method delete

Do not print or send this part of the message anymore.  See deleted().
The time stamp of the moment of deletion is stored as value.  When the same
message is deleted more than once, the first time stamp will stay.

=examples

 $message->part(2)->delete;
 $part->deleted(1);
 delete $part;

=cut

sub delete() { shift->{MMP_deleted} ||= time }

#------------------------------------------

=method deleted [BOOLEAN]

Set the delete flag for this part of the multipart message body.  Without
argument, the method returns the same is the isDeleted() method, which is
prefered.  When a true value is given, delete() is called.

=cut

sub deleted(;$)
{   my $self = shift;
      ! @_      ? $self->isDeleted   # compat 2.036
    : ! (shift) ? ($self->{MMP_deleted} = undef)
    :             $self->delete;
}

#------------------------------------------

=method isDeleted

Returns the moment (as the time function returns) when the message part was
flagged for deletion, or C<undef> when the part is not deleted.

=examples

 next if $part->isDeleted;

 if(my $when = $part->isDeleted) {
    print scalar localtime $when;
 }

=cut

sub isDeleted() { shift->{MMP_deleted} }

#------------------------------------------

sub container(;$)
{   my $self = shift;
    @_ ? $self->{MMP_container} = shift : $self->{MMP_container};
}

#------------------------------------------

sub toplevel()
{   my $body = shift->container or return;
    my $msg  = $body->message   or return;
    $msg->toplevel;
}

#------------------------------------------

sub isPart() { 1 }

#------------------------------------------

=method printEscapedFrom FILEHANDLE

Prints the message part, but all lines which start with 'From ' will get
a leading C<gt>.  See Mail::Message::Body::printEscapedFrom().

=cut

sub printEscapedFrom($)
{   my ($self, $out) = @_;
    $self->head->print($out);
    $self->body->printEscapedFrom($out);
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

sub readFromParser($;$)
{   my ($self, $parser, $bodytype) = @_;

    my $head = $self->readHead($parser)
            || Mail::Message::Head::Complete->new
                 ( message     => $self
                 , field_type  => $self->{MM_field_type}
                 , $self->logSettings
                 );

    my $body = $self->readBody($parser, $head, $bodytype)
            || Mail::Message::Body::Lines->new(data => []);

    $self->head($head);
    $self->storeBody($body);
    $self;
}

#------------------------------------------

1;
