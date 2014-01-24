use strict;
use warnings;

package Mail::Message::Part;
use base 'Mail::Message';

use Scalar::Util    'weaken';
use Carp;

=chapter NAME

Mail::Message::Part - a part of a message, but a message by itself

=chapter SYNOPSIS

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

=chapter DESCRIPTION

A C<Mail::Message::Part> object contains a message which is included in
the body of an other message.  For instance I<attachments> are I<parts>.

READ M<Mail::Message> FIRST.  A part is a special message: it has a
reference to its parent message, and will usually not be sub-classed
into mail folder specific variants.

=chapter METHODS

=c_method new %options
Create a message part.

=default  head     <empty header>
=requires container BODY
Reference to the parental M<Mail::Message::Body> object where this part
is a member of.  That object may be a M<Mail::Message::Body::Multipart>
or a M<Mail::Message::Body::Nested>.

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{head} ||= Mail::Message::Head::Complete->new;

    $self->SUPER::init($args);

    confess "No container specified for part.\n"
        unless exists $args->{container};

    weaken($self->{MMP_container})
       if $self->{MMP_container} = $args->{container};

    $self;
}

=c_method coerce <$body|$message>, $multipart, @headers
Transforms a $body or $message to a real message part.  The $multipart
refers to the parental body.

When ta $body is specified, extra @headers can be supplied as well.
Bodies are coerced into message parts by calling M<buildFromBody()>.
If you specify a $message residing in a folder, this message will
automatically be cloned.
=cut

sub coerce($@)
{   my ($class, $thing, $container) = (shift, shift, shift);
    if($thing->isa($class))
    {   $thing->container($container);
        return $thing;
    }

    return $class->buildFromBody($thing, $container, @_)
        if $thing->isa('Mail::Message::Body');

    # Although cloning is a Bad Thing(tm), we must avoid modifying
    # header fields of messages which reside in a folder.
    my $message = $thing->isa('Mail::Box::Message') ? $thing->clone : $thing;

    my $part    = $class->SUPER::coerce($message);
    $part->container($container);
    $part;
}

=c_method buildFromBody $body, $container, $headers
Shape a message part around a $body.  Bodies have information about their
content in them, which is used to construct a header for the message.
Next to that, more $headers can be specified.  No headers are obligatory.
No extra headers are fabricated automatically.
=example
 my $multi = Mail::Message::Body::Multipart->new;
 my $part  = Mail::Message::Part->buildFromBody($body, $multi);
=cut

sub buildFromBody($$;@)
{   my ($class, $body, $container) = (shift, shift, shift);
    my @log  = $body->logSettings;

    my $head = Mail::Message::Head::Complete->new(@log);
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

sub container(;$)
{   my $self = shift;
    return $self->{MMP_container} unless @_;

    $self->{MMP_container} = shift;
    weaken($self->{MMP_container});
}

sub toplevel()
{   my $body = shift->container or return;
    my $msg  = $body->message   or return;
    $msg->toplevel;
}

sub isPart() { 1 }

sub partNumber()
{   my $self = shift;
    my $body = $self->container or confess 'no container';
    $body->partNumberOf($self);
}

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
    $self->storeBody($body->contentInfoFrom($head));
    $self;
}

#-----------------
=section The message

=method printEscapedFrom $fh
Prints the message part, but all lines which start with 'From ' will get
a leading E<gt>.  See M<Mail::Message::Body::printEscapedFrom()>.
=cut

sub printEscapedFrom($)
{   my ($self, $out) = @_;
    $self->head->print($out);
    $self->body->printEscapedFrom($out);
}

=section Cleanup

=method destruct
Message parts can not be destructed per part: only whole messages can
be forcefully freed from memory.  Of course, you can M<delete()> separate
parts, which only sets a flag not to write a part again.  Furthermore,
you may cosider M<rebuild()> to get rit of deleted parts.

=error You cannot destruct message parts, only whole messages
Message parts can not be destructed per part: only whole messages can
be forcefully freed from memory. Consider M<delete()> or M<rebuild()>.
=cut

sub destruct()
{  my $self = shift;
   $self->log(ERROR =>'You cannot destruct message parts, only whole messages');
   undef;
}

1;
