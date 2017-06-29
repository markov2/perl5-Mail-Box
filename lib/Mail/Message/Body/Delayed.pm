use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Object::Realize::Later
    becomes          => 'Mail::Message::Body',
    realize          => 'load',
    warn_realization => 0,
    believe_caller   => 1;

use Carp;
use Scalar::Util 'weaken';

=chapter NAME

Mail::Message::Body::Delayed - body of a Mail::Message but not read yet.

=chapter SYNOPSIS

 See M<Mail::Message::Body>

=chapter DESCRIPTION

Message bodies of this type will be replaced by another type the moment you
access the content.  In this documentation you will find the description of
how a message body gets delay loaded.

=chapter OVERLOADED

=overload @{}

When a body object is used as being an array reference, the lines of
the body are returned.  This is the same as using the C<lines> method.

=overload bool

Always returns a true value, which is needed to have overloaded
objects to be used as in C<if($body)>.  Otherwise, C<if(defined $body)>
would be needed to avoid a runtime error.

=overload ""

(stringification) Returns the body as string --which will trigger
completion-- unless called to produce a string for C<Carp>.  The latter
to avoid deep recursions.

=example stringification of delayed body

 print $msg->body;   # implicit by print

 my $body = $msg->body;
 my $x    = "$body"; # explicit by interpolation

=cut

use overload '""'    => 'string_unless_carp'
           , bool    => sub {1}
           , '@{}'   => sub {shift->load->lines};

#------------------------------------------

=chapter METHODS

=c_method new %options

=requires  message MESSAGE

The MESSAGE object which contains this delayed body.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMB_seqnr}    = -1;  # for overloaded body comparison
    $self->{MMBD_message} = $args->{message}
        or $self->log(INTERNAL => "A message must be specified to a delayed body.");

    weaken($self->{MMBD_message});
    $self;
}

#------------------------------------------

=section The body

=method message

=cut

sub message() { shift->{MMBD_message} }

#------------------------------------------

=section About to the payload

=method modified

=cut

sub modified(;$)
{   return 0 if @_==1 || !$_[1];
    shift->forceRealize(shift);
}

#------------------------------------------

=method isModified

=cut

sub isModified() { 0 }

#------------------------------------------

=method isDelayed

=cut

sub isDelayed()   {1}

#------------------------------------------

=method isMultipart

=cut

sub isMultipart() {shift->message->head->isMultipart}

#------------------------------------------

=method guessSize

=cut

sub guessSize()   {shift->{MMBD_size}}

#------------------------------------------

=method nrLines

=cut

sub nrLines()
{   my ($self) = @_;
      defined $self->{MMBD_lines}
    ? $self->{MMBD_lines}
    : $_[0]->forceRealize->nrLines;
}

#------------------------------------------

sub string_unless_carp()
{   my $self = shift;
    return $self->load->string unless (caller)[0] eq 'Carp';

    (my $class = ref $self) =~ s/^Mail::Message/MM/g;
    "$class object";
}

#------------------------------------------

=section Internals

=method read $parser, $head, $bodytype

=cut

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    $self->{MMBD_parser} = $parser;

    @$self{ qw/MMBD_begin MMBD_end MMBD_size MMBD_lines/ }
        = $parser->bodyDelayed(@_);

    $self;
}

#------------------------------------------

=method fileLocation [$begin, $end]

=cut

sub fileLocation(;@) {
   my $self = shift;
   return @$self{ qw/MMBD_begin MMBD_end/ } unless @_;
   @$self{ qw/MMBD_begin MMBD_end/ } = @_;
}

#------------------------------------------

=method moveLocation $distance

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMBD_begin} -= $dist;
    $self->{MMBD_end}   -= $dist;
    $self;
}

#------------------------------------------

=method load

Returns the loaded version of this body.

=cut

sub load() {$_[0] = $_[0]->message->loadBody}

#------------------------------------------

=section Error handling

=cut

1;
