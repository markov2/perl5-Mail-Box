use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Object::Realize::Later
    becomes          => 'Mail::Message::Body',
    realize          => 'load',
    warn_realization => 0,
    believe_caller   => 1;

use overload '""'    => 'string_unless_carp'
           , bool    => sub {1}
           , '@{}'   => sub {shift->load->lines};

use Carp;
use Scalar::Util 'weaken';

=head1 NAME

Mail::Message::Body::Delayed - body of a Mail::Message but not read yet.

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

Message bodies of this type will be replaced by another type the moment you
access the content.  In this documentation you will find the description of
how a message body gets delay loaded.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=option  message MESSAGE
=default message <required>

The MESSAGE object which contains this delayed body.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMB_seqnr}    = -1;  # for overloaded body comparison
    $self->{MMBD_message} = $args->{message}
        or croak "A message must be specified to a delayed body.";

    weaken($self->{MMBD_message});
    $self;
}

#------------------------------------------

=head2 The Body

=cut

#------------------------------------------

=method message

=cut

sub message() {shift->{MMBD_message}}

#------------------------------------------

sub modified(;$)
{   return 0 if @_==1 || !$_[1];
    shift->forceRealize(shift);
}

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

=head2 About the Payload

=cut

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

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method read PARSER, HEAD, BODYTYPE

=cut

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    $self->{MMBD_parser} = $parser;

    @$self{ qw/MMBD_begin MMBD_end MMBD_size MMBD_lines/ }
        = $parser->bodyDelayed(@_);

    $self;
}

#------------------------------------------

=method fileLocation BEGIN, END

=cut

sub fileLocation(;@) {
   my $self = shift;
   return @$self{ qw/MMBD_begin MMBD_end/ } unless @_;
   @$self{ qw/MMBD_begin MMBD_end/ } = @_;
}

#------------------------------------------

=method moveLocation DISTANCE

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

1;
