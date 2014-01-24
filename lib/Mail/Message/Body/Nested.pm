use strict;
use warnings;

package Mail::Message::Body::Nested;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

use Carp;

=chapter NAME

Mail::Message::Body::Nested - body of a message which contains a message

=chapter SYNOPSIS

 See M<Mail::Message::Body>

 if($body->isNested) {
    my $nest = $body->nested;
    $nest->delete;
 }

=chapter DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message contains a nested message, like C<message/rfc822>.

A nested message is different from a multipart message which contains
only one element, because a nested message has a full set of message
header fields defined by the RFC882, where a part of a multipart has
only a few.  But because we do not keep track whether all fields are
presented, a C<Mail::Message::Part> is used anyway.

=chapter METHODS

=c_method new %options

=default mime_type C<'message/rfc822'>

=option  nested MESSAGE
=default nested undef

The message which is encapsulated within this body.

=examples

 my $msg   = $folder->message(3);
 my $encaps= Mail::Message::Body::Nested->new(nested => $msg);

 # The body will be coerced into a message, which lacks a few
 # lines but we do not bother.
 my $intro = M<Mail::Message::Body>->new(data => ...);
 my $body  = Mail::Message::Body::Nested->new(nested  => $intro);

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{mime_type} ||= 'message/rfc822';

    $self->SUPER::init($args);

    my $nested;
    if(my $raw = $args->{nested})
    {   $nested = Mail::Message::Part->coerce($raw, $self);

        croak 'Data not convertible to a message (type is ', ref $raw,")\n"
            unless defined $nested;
    }

    $self->{MMBN_nested} = $nested;
    $self;
}

sub isNested() {1}

sub isBinary() { shift->nested->body->isBinary }

sub clone()
{   my $self     = shift;

    ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , nested   => $self->nested->clone
     );
}

sub nrLines() { shift->nested->nrLines }

sub size()    { shift->nested->size }

sub string()
{    my $nested = shift->nested;
     defined $nested ? $nested->string : '';
}

sub lines()
{    my $nested = shift->nested;
     defined $nested ? ($nested->lines) : ();
}

sub file()
{    my $nested = shift->nested;
     defined $nested ? $nested->file : undef;
}

sub print(;$)
{   my $self = shift;
    $self->nested->print(shift || select);
}

sub partNumberOf($)
{   my ($self, $part) = @_;
    $self->message->partNumber;
}

=method foreachLine(CODE)
It is NOT possible to call some code for each line of a nested
because that would damage the header of the encapsulated message

=error You cannot use foreachLine on a nested
M<foreachLine()> should be used on decoded message bodies only, because
it would modify the header of the encapsulated message. which is
clearly not acceptible.

=cut

sub foreachLine($)
{   my ($self, $code) = @_;
    $self->log(ERROR => "You cannot use foreachLine on a nested");
    confess;
}

sub check() { shift->forNested( sub {$_[1]->check} ) }

sub encode(@)
{   my ($self, %args) = @_;
    $self->forNested( sub {$_[1]->encode(%args)} );
}

sub encoded() { shift->forNested( sub {$_[1]->encoded} ) }

sub read($$$$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $nest = Mail::Message::Part->new(container => undef);
    $nest->readFromParser($parser, $bodytype)
       or return;

    $nest->container($self);
    $self->{MMBN_nested} = $nest;
    $self;
}

sub fileLocation()
{   my $nested   = shift->nested;

    ( ($nested->head->fileLocation)[0]
    , ($nested->body->fileLocation)[1]
    );
}

sub endsOnNewline() { shift->nested->body->endsOnNewline }

sub moveLocation($)
{   my $self   = shift;
    my $nested = $self->nested;
    my $dist   = shift or return $self;  # no move

    $nested->head->moveLocation($dist);
    $nested->body->moveLocation($dist);
    $self;
}

=section Access to the payload

=method nested
Returns the M<Mail::Message::Part> message which is enclosed within
this body.
=cut

sub nested() { shift->{MMBN_nested} }

=method forNested CODE

Execute the CODE for the nested message.  This returns a new
nested body object.  Returns C<undef> when the CODE returns C<undef>.

=cut

sub forNested($)
{   my ($self, $code) = @_;
    my $nested    = $self->nested;
    my $body      = $nested->body;

    my $new_body  = $code->($self, $body)
       or return;

    return $self if $new_body == $body;

    my $new_nested  = Mail::Message::Part->new
       ( head      => $nested->head->clone
       , container => undef
       );

    $new_nested->body($new_body);

    my $created = (ref $self)->new
      ( based_on => $self
      , nested   => $new_nested
      );

    $new_nested->container($created);
    $created;
}

sub toplevel() { my $msg = shift->message; $msg ? $msg->toplevel : undef}

1;
