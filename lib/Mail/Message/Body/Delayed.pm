#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Message::Body::Delayed;
use parent 'Mail::Reporter';

use strict;
use warnings;

use Object::Realize::Later
	becomes          => 'Mail::Message::Body',
	realize          => 'load',
	warn_realization => 0,
	believe_caller   => 1;

use Carp;
use Scalar::Util     qw/weaken/;

#--------------------
=chapter NAME

Mail::Message::Body::Delayed - body of a Mail::Message but not read yet.

=chapter SYNOPSIS

  See Mail::Message::Body

=chapter DESCRIPTION

Message bodies of this type will be replaced by another type the moment you
access the content.  In this documentation you will find the description of
how a message body gets delay loaded.

=chapter OVERLOADED

=overload @{} access as ARRAY
When a body object is used as being an array reference, the lines of
the body are returned.  This is the same as using the C<lines> method.

=overload bool existence
Always returns a true value, which is needed to have overloaded
objects to be used as in C<if($body)>.  Otherwise, C<if(defined $body)>
would be needed to avoid a runtime error.

=overload "" stringification
Returns the body as string --which will trigger completion-- unless called
to produce a string for C<Carp>.  The latter to avoid deep recursions.

=example stringification of delayed body

  print $msg->body;   # implicit by print

  my $body = $msg->body;
  my $x    = "$body"; # explicit by interpolation

=cut

use overload
	'""'    => 'string_unless_carp',
	bool    => sub {1},
	'@{}'   => sub { $_[0]->load->lines };

#--------------------
=chapter METHODS

=c_method new %options
=requires  message MESSAGE
The MESSAGE object which contains this delayed body.
=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);

	$self->{MMB_seqnr}    = -1;  # for overloaded body comparison
	$self->{MMBD_message} = $args->{message}
		or $self->log(INTERNAL => "A message must be specified to a delayed body.");

	weaken($self->{MMBD_message});
	$self;
}

#--------------------
=section The body

=method message
=cut

sub message() { $_[0]->{MMBD_message} }

#--------------------
=section About to the payload

=method modified
=cut

sub modified(;$)
{	return 0 if @_==1 || !$_[1];
	shift->forceRealize(shift);
}

=method isModified
=method isDelayed
=method isMultipart
=method guessSize
=cut

sub isModified()  {0}
sub isDelayed()   {1}
sub isMultipart() { $_[0]->message->head->isMultipart }
sub guessSize()   { $_[0]->{MMBD_size} }

=method nrLines
=cut

sub nrLines() { $_[0]->{MMBD_lines} // $_[0]->forceRealize->nrLines }

sub string_unless_carp()
{	my $self = shift;
	return $self->load->string if (caller)[0] ne 'Carp';

	my $class = ref $self =~ s/^Mail::Message/MM/gr;
	"$class object";
}

#--------------------
=section Internals

=method read $parser, $head, $bodytype
=cut

sub read($$;$@)
{	my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
	$self->{MMBD_parser} = $parser;

	@$self{ qw/MMBD_begin MMBD_end MMBD_size MMBD_lines/ } = $parser->bodyDelayed(@_);
	$self;
}

=method fileLocation [$begin, $end]
=cut

sub fileLocation(;@) {
	my $self = shift;
	@_ ? (@$self{ qw/MMBD_begin MMBD_end/ } = @_) : @$self{ qw/MMBD_begin MMBD_end/ };
}

=method moveLocation $distance
=cut

sub moveLocation($)
{	my ($self, $dist) = @_;
	$self->{MMBD_begin} -= $dist;
	$self->{MMBD_end}   -= $dist;
	$self;
}

=method load
Returns the loaded version of this body.
=cut

sub load() { $_[0] = $_[0]->message->loadBody }

1;
