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
         my $attachbody = $part->head;
         my $attachhead = $part->body;
     }
 }

=head1 DESCRIPTION

A Mail::Message::Part object contains a message which is included in
an other message.  For instance I<attachments> are I<parts>.

READ Mail::Message FIRST.  A part is a special message: it has a
reference to its parent message, and will usually not be sub-classed
into mail-folder-specific variants.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

Create a message part.

=option  parent MESSAGE
=default parent <obligatory>

Reference to the parental Mail::Message object where this
part is a member of.  That object may be a part itself.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMP_parent} = $args->{parent}
        or confess "No parent specified for part.\n";

    $self;
}

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=method coerce BODY|MESSAGE, PARENT-BODY

Transforms a BODY or MESSAGE to a real message part.  The MULTIPART refers
to the parental body.

=cut

sub coerce($@)
{   my ($class, $message, $parent) = @_;

    my $part = $class->SUPER::coerce($message);
    $part->{MMP_parent} = $parent;

    $part;
}

#------------------------------------------

=head2 The Message

=cut

#------------------------------------------

=method delete

Do not print or send this part of the message anymore.

=cut

sub delete() {shift->deleted(1)}

#------------------------------------------

=method deleted [BOOLEAN]

Returns whether this part is still in the body or not, optionally
after setting it to the BOOLEAN.

=cut

sub deleted(;$)
{   my $self = shift;
    return $self->{MMP_deleted} unless @_;

    $self->toplevel->modified(1);
    $self->{MMP_deleted} = shift;
}

#------------------------------------------

sub parent() { shift->{MMP_parent} }

#------------------------------------------

sub toplevel() { shift->parent->toplevel }

#------------------------------------------

sub isPart() { 1 }

#------------------------------------------

1;
