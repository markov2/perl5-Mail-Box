
use strict;

package Mail::Message;

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Carp;
use Scalar::Util 'blessed';
use IO::Lines;

=chapter NAME

Mail::Message::Construct - extends the functionality of a Mail::Message

=chapter SYNOPSIS

 # See M<Mail::Message>

=chapter DESCRIPTION

Complex functionality on M<Mail::Message> objects is implemented in
different files which are autoloaded.  This file implements the
functionality related to creating message replies.

=chapter METHODS

=method AUTOLOAD

When an unknown method is called on this message, this may mean that
not all code is compiled.  For performance reasons, most of the
complex activities on messages are dynamically loaded from other
packages.  An error will be produced when loading does not help resolving
the requested method.

=cut

our %locations =
(
  bounce             => 'Bounce'

, build              => 'Build'
, buildFromBody      => 'Build'

, forward            => 'Forward'
, forwardNo          => 'Forward'
, forwardInline      => 'Forward'
, forwardAttach      => 'Forward'
, forwardEncapsulate => 'Forward'
, forwardSubject     => 'Forward'
, forwardPrelude     => 'Forward'
, forwardPostlude    => 'Forward'

, read               => 'Read'

, rebuild            => 'Rebuild'

, reply              => 'Reply'
, replySubject       => 'Reply'
, replyPrelude       => 'Reply'

, string             => 'Text'
, lines              => 'Text'
, file               => 'Text'
, printStructure     => 'Text'
);

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;

    if(my $mod = $locations{$call})
    {   eval "require Mail::Message::Construct::$mod";
        die $@ if $@;
        return $self->$call(@_);
    }

    our @ISA;                    # produce error via Mail::Reporter
    $call = "${ISA[0]}::$call";
    $self->$call(@_);
}

1;
