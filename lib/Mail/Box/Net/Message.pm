#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Net::Message;
use parent 'Mail::Box::Message';

use strict;
use warnings;

use Carp;

#--------------------
=chapter NAME

Mail::Box::Net::Message - one message from a distant folder

=chapter SYNOPSIS

  my $folder = Mail::Box:POP3->new(...);
  my $message = $folder->message(10);

=chapter DESCRIPTION

A Mail::Box::Net::Message represents one message in a folder which
can only be accessed via some kind of protocol.  On this moment, only
a POP3 client is available.  IMAP, DBI, and NNTP are other candidates.

=chapter METHODS

=c_method new %options

=option  unique STRING
=default unique <unique string>
The unique keys which identifies this message on the remote server.

=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);
	$self->unique($args->{unique});
	$self;
}

#--------------------
=section Attributes

=method unique [STRING|undef]
Returns the name of the file in which this message is actually stored.  This
will return undef when the message is not stored in a file.  When a STRING
is specified, a new identifier is stored first.
=cut

sub unique(;$)
{	my $self = shift;
	@_ ? $self->{MBNM_unique} = shift : $self->{MBNM_unique};
}

#--------------------
=section Internals
=cut

sub loadHead()
{	my $self     = shift;
	my $head     = $self->head;
	$head->isDelayed or return $head;

	my $folder   = $self->folder;
	$folder->lazyPermitted(1);

	my $parser   = $self->parser or return;
	$self->readFromParser($parser);

	$folder->lazyPermitted(0);

	$self->log(PROGRESS => 'Loaded delayed head.');
	$self->head;
}

=method loadBody
=error Unable to read delayed head.
=error Unable to read delayed body.
=cut

sub loadBody()
{	my $self     = shift;

	my $body     = $self->body;
	$body->isDelayed or return;

	my $head     = $self->head;
	my $parser   = $self->parser or return;

	if($head->isDelayed)
	{	$head = $self->readHead($parser)
			or $self->log(ERROR => 'Unable to read delayed head.'), return;

		$self->log(PROGRESS => 'Loaded delayed head.');
		$self->head($head);
	}
	else
	{	my ($begin, $end) = $body->fileLocation;
		$parser->filePosition($begin);
	}

	my $newbody  = $self->readBody($parser, $head)
		or $self->log(ERROR => 'Unable to read delayed body.'), return;

	$self->log(PROGRESS => 'Loaded delayed body.');
	$self->storeBody($newbody->contentInfoFrom($head));
}

1;
