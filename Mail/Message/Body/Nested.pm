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

=method new OPTIONS

=default mime_type 'message/rfc822'

=option  nested =E<gt> MESSAGE
=default nested undef

The message which is nested within this one.

=examples

 my $intro = Mail::Message::Body->new(data => ...);
 my $body  = Mail::Message::Body::Nested->new(nested  => $intro);

=cut

#------------------------------------------

sub init($)
{   my ($self, $args) = @_;
    $args->{mime_type} ||= 'message/rfc822';

    $self->SUPER::init($args);

    my $nested;
    if(my $raw = $args->{nested})
    {   my $nested = Mail::Message::Part->coerce($raw, $self);

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

sub isBinary() {shift->nested->isBinary}

#------------------------------------------

sub clone()
{   my $self     = shift;

    my $body     = ref($self)->new
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
     defined $nested ? $nested->lines : ();
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
    $self;
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

    return $body if $new_body == $body;

    my $new_nested  = Mail::Message->new(head => $nested->head->clone);
    $new_nested->body($new_body);

    (ref $self)->new
      ( based_on => $self
      , nested   => $new_nested
      );
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

    my $raw = Mail::Message->new;
    $raw->readFromParser($parser, $bodytype)
       or return;

    my $cooked = Mail::Message::Part->coerce($raw, $self);
    $self->{MMBN_nested} = $cooked;
    $self;
}


#-------------------------------------------

1;
