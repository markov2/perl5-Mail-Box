
use strict;

package Mail::Message::Head::Delayed;
use base 'Mail::Message::Head';

use Object::Realize::Later
    becomes          => 'Mail::Message::Head::Complete',
    realize          => 'load',
    believe_caller   => 1;

use Carp;
use Date::Parse;
use Scalar::Util 'weaken';

=chapter NAME

Mail::Message::Head::Delayed - a not-read header of a Mail::Message

=chapter SYNOPSIS

 my Mail::Message::Head::Delayed $delayed = ...;
 $delayed->isa('Mail::Message::Head')  # true
 $delayed->guessBodySize               # undef
 $delayed->isDelayed                   # true

=chapter DESCRIPTION

This object is used as place-holder, to be replaced
by a M<Mail::Message::Head> when someone accesses the header of a message.

=chapter METHODS

=section Constructors

=method build FIELDS

You cannot create a delayed header with fields.

=error Cannot build() a delayed header.

A delayed message header cannot contain any information, so cannot be
build.  You can construct complete or subset headers.

=cut

sub build(@) {shift->log(ERROR => "Cannot build() a delayed header.") }

#------------------------------------------

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    if(defined $args->{message})
    {   $self->{MMHD_message} = $args->{message};
        weaken($self->{MMHD_message});
    }

    $self;
}

#------------------------------------------

sub isDelayed() {1}

#------------------------------------------

sub modified(;$)
{   return 0 if @_==1 || !$_[1];
    shift->forceRealize->modified(1);
}

#------------------------------------------

sub isModified() { 0 }

#------------------------------------------

=section Access to the header

=method get NAME [,INDEX]

Get the information about the header line NAME.  Realization will
take place.

=cut

sub get($;$)
{   my $self = shift;
    $self->load->get(@_);
}

#------------------------------------------

=section About the body

=method guessBodySize

On a delayed head, this retuns C<undef>, because when there is no header
there is also no body.

For messages in directory or network organized folders,
M<Mail::Message::size()> usually will give a figure for the whole message
without much cost.  Subtract a few hundred bytes for the header, and
you will get a good estimate.

=cut

sub guessBodySize() {undef}

#-------------------------------------------

=method guessTimeStamp

Make a guess about when the message was origanally posted.
On a delayed head, this returns C<undef>.
For messages in directory or network organized folders,
M<Mail::Message::timestamp()> usually will give a figure without much cost.

=cut

sub guessTimestamp() {undef}

#------------------------------------------

=section Internals

=cut

sub read($)
{   my ($self, $parser, $headtype, $bodytype)  = @_;

#   $parser->skipHeader not implemented... returns where
    $self->{MMH_where}   = 0;
    $self;
}

#------------------------------------------

sub load() {$_[0] = $_[0]->message->loadHead}

#------------------------------------------

sub setNoRealize($) { shift->log(INTERNAL => "Setting field on a delayed?") }

#-------------------------------------------

1;
