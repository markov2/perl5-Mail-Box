
use strict;
use warnings;

package Mail::Box::Net::Message;
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::Net::Message - one message from a distant folder

=head1 SYNOPSIS

 my $folder = new Mail::Box::POP3 ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A Mail::Box::Net::Message represents one message in a folder which
can only be accessed via some kind of protocol.  On this moment, only
a POP3 client is available.  IMAP, DBI, and NNTP are other candidates.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=option  unique STRING
=default unique <unique string>

The unique keys which identifies this message on the remote server.

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $unique = $args->{unique}
        or croak "No unique keys for this net message.";

    $self->unique($unique);

    $self;
}

#-------------------------------------------

=method unique [STRING]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.  When a STRING
is specified, a new identifier is stored first.

=cut

sub unique(;$)
{   my $self = shift;
    @_ ? $self->{MBNM_unique} = shift : $self->{MBNM_unique};
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    my $folder   = $self->folder;
    $folder->lazyPermitted(1);

    my $parser   = $self->parser or return;
    $self->readFromParser($parser);

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head.');
    $self->head;
}

#-------------------------------------------

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->head;
    my $parser   = $self->parser or return;

    if($head->isDelayed)
    {   $head = $self->readHead($parser);
        if(defined $head)
        {   $self->log(PROGRESS => 'Loaded delayed head.');
            $self->head($head);
        }
        else
        {   $self->log(ERROR => 'Unable to read delayed head.');
            return;
        }
    }
    else
    {   my ($begin, $end) = $body->fileLocation;
        $parser->filePosition($begin);
    }

    my $newbody  = $self->readBody($parser, $head);
    unless(defined $newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);
}

#-------------------------------------------

1;