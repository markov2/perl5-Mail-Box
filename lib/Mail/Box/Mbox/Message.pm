#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Mbox::Message;
use parent 'Mail::Box::File::Message';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw// ];

#--------------------
=chapter NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=chapter SYNOPSIS

  my $folder  = Mail::Box::Mbox->new(folder => $ENV{MAIL}, ...);
  my $message = $folder->message(0);

=chapter DESCRIPTION

Maintain one message in an Mail::Box::Mbox folder.

=chapter METHODS

=cut

sub head(;$$)
{	my $self  = shift;
	return $self->SUPER::head unless @_;

	my ($head, $labels) = @_;
	$self->SUPER::head($head, $labels);

	$self->statusToLabels if $head && !$head->isDelayed;
	$head;
}

sub label(@)
{	my $self   = shift;
	$self->loadHead;    # be sure the status fields have been read
	$self->SUPER::label(@_);
}

sub labels(@)
{	my $self   = shift;
	$self->loadHead;    # be sure the status fields have been read
	$self->SUPER::labels(@_);
}

1;
