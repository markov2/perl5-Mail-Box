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

    confess "No parent specified for part.\n"
        unless exists $args->{parent};

    $self->{MMP_parent} = $args->{parent};
    $self;
}

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=method buildFromBody BODY, PARENT, HEADERS

(Class method) 
Shape a message around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the message.
Next to that, more HEADERS can be specified.  No headers are obligatory.
No extra headers are fabricated automatically.

=example

 my $part = Mail::Message::Part $body, $parent;

=cut

sub buildFromBody($$;@)
{   my ($class, $body, $parent) = (shift, shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $part = $class->new
     ( head   => $head
     , parent => $parent
     , @log
     );

    $part->storeBody($body->check);
    $part->statusToLabels;
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
{   my ($class, $thing, $parent) = (shift, shift, shift);

    return $class->buildFromBody($thing, $parent, @_)
        if $thing->isa('Mail::Message::Body');

    my $message = $thing->isa('Mail::Box::Message') ? $thing->clone : $thing;

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

sub parent(;$)
{   my $self = shift;
    @_ ? $self->{MMP_parent} = shift : $self->{MMP_parent};
}

#------------------------------------------

sub toplevel() { shift->parent->toplevel }

#------------------------------------------

sub isPart() { 1 }

#------------------------------------------

1;
