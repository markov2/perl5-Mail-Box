
use strict;
use warnings;

package Mail::Box::POP3::Message;
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

=chapter NAME

Mail::Box::POP3::Message - one message on a POP3 server

=chapter SYNOPSIS

 my $folder = new Mail::Box::POP3 ...
 my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::POP3::Message> represents one message on a POP3 server,
maintained by a M<Mail::Box::POP3> folder. Each message is stored as
separate entity on the server, and maybe temporarily in your program
as well.

=chapter METHODS

=c_method new OPTIONS

=default body_type M<Mail::Message::Body::Lines>

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
    $self;
}

#-------------------------------------------

=method size

Returns the size of this message.  If the message is still on the remote
server, POP is used to ask for the size.  When the message is already loaded
onto the local system, the size of the parsed message is taken.  These
sizes can differ because the difference in line-ending representation.

=cut

sub size($)
{   my $self = shift;
    
    return $self->SUPER::size
        unless $self->isDelayed;

    $self->folder->popClient->messageSize($self->unique);
}

#-------------------------------------------

sub delete()
{   my $self = shift;
    $self->folder->popClient->deleted(1, $self->unique);
    $self->SUPER::delete;
}

#-------------------------------------------

sub deleted(;$)
{   my $self   = shift;
    return $self->SUPER::deleted unless @_;

    my $set    = shift;
    $self->folder->popClient->deleted(0, $self->unique)
       unless $set;

    $self->SUPER::deleted($set);
}

#-------------------------------------------

=section Internals

=cut

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    $self->head($self->folder->getHead($self));
}

#-------------------------------------------

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    (my $head, $body) = $self->folder->getHeadAndBody($self);
    $self->head($head) if $head->isDelayed;
    $self->storeBody($body);
}

#-------------------------------------------

1;