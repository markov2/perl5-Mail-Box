use strict;
use warnings;

package Mail::Message::Body::Nested;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

use Carp;

=head1 NAME

Mail::Message::Body::Nested - body of a message which contains a message

=head1 SYNOPSIS

 See Mail::Message::Body, plus

 if($body->isNested) {
    my ($nest) = $body->nested;
    $body->part(1)->delete;
 }

=head1 DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message contains a nested message, like message/rfc822.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

=default mime_type 'message/rfc822'

=option  nested MESSAGE-PART
=default nested undef

The message which is nested within this one.

=examples

 my $intro = Mail::Message::Body->new(data => ...);
 my $body  = Mail::Message::Body::Nested->new(nested  => $intro);

 my $msg   = $folder->message(3);
 my $encaps= Mail::Message::Body::Nested->new(nested => $msg);

=cut

#------------------------------------------

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

    my $based = $args->{based_on};

    $self->{MMBN_nested}
       = !$based || defined $nested  ? $nested
       : $based->isNested            ? $based->nested
       : undef;

    $self;
}

#------------------------------------------

=head2 The Body

=cut

#------------------------------------------

sub isNested() {1}

#------------------------------------------

sub isBinary() {shift->nested->body->isBinary}

#------------------------------------------

sub clone()
{   my $self     = shift;

    ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , nested   => $self->nested->clone
     );
}

#------------------------------------------

=head2 About the Payload

=cut

#------------------------------------------

sub nrLines() { shift->nested->nrLines }

#------------------------------------------

sub size()    { shift->nested->size }

#------------------------------------------

=head2 Access to the Payload

=cut

#------------------------------------------

=method nested

Returns the message which is enclosed within this body.

=cut

sub nested() { shift->{MMBN_nested} }

#------------------------------------------

sub string()
{    my $nested = shift->nested;
     defined $nested ? $nested->string : '';
}

#------------------------------------------

sub lines()
{    my $nested = shift->nested;
     defined $nested ? ($nested->lines) : ();
}

#------------------------------------------

sub file()
{    my $nested = shift->nested;
     defined $nested ? $nested->file : undef;
}

#------------------------------------------

sub print(;$)
{   my $self = shift;
    $self->nested->print(shift || select);
}

#------------------------------------------

sub printEscapedFrom($)
{   my $self = shift;
    $self->nested->printEscapedFrom(shift);
}

#------------------------------------------

=method forNested CODE

Execute the CODE for the nested message.  This returns a new body object.

=cut

sub forNested($)
{   my ($self, $code) = @_;
    my $nested    = $self->nested;
    my $body      = $nested->body;
    my $new_body  = $code->($self, $body);

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

#------------------------------------------

=head2 Constructing a Body

=cut

#------------------------------------------

sub check() { shift->forNested( sub {$_[1]->check} ) }

#------------------------------------------

sub encode(@)
{   my ($self, %args) = @_;
    $self->forNested( sub {$_[1]->encode(%args)} );
}

#------------------------------------------

sub encoded() { shift->forNested( sub {$_[1]->encoded} ) }

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

sub read($$$$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $nest = Mail::Message::Part->new(container => undef);
    $nest->readFromParser($parser, $bodytype)
       or return;

    $nest->container($self);
    $self->{MMBN_nested} = $nest;
    $self;
}

#-------------------------------------------

sub fileLocation(;$$) { shift->{MMBN_nested}->fileLocation(@_) }

#-------------------------------------------

1;
