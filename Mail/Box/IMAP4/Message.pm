
use strict;
use warnings;

package Mail::Box::IMAP4::Message;
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::IMAP4::Message - one message on a IMAP4 server

=head1 SYNOPSIS

 my $folder = new Mail::Box::IMAP4 ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A Mail::Box::IMAP4::Message represents one message on a IMAP4 server,
maintained by a Mail::Box::IMAP4 folder. Each message is stored as
separate entity on the server, and maybe temporarily in your program
as well.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=default body_type 'Mail::Message::Body::Lines';

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
    $self;
}

#-------------------------------------------

=head2 The Message

=cut

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

    $self->folder->imapClient->messageSize($self->unique);
}

#-------------------------------------------

=head2 Labels

=cut

#-------------------------------------------

sub deleted(;$)
{   my $self   = shift;
    return $self->SUPER::deleted unless @_;

    my $set    = shift;
    $self->folder->imapClient->deleted($set, $self->unique);
    $self->SUPER::deleted($set);
}

#-------------------------------------------

=method label LABEL, [VALUE, [LABEL, VALUE, ...]]

With only one argument, the value related to LABEL is returned.  With
more that one argument, the list is interpreted a LABEL-VALUE pairs
to be set.

The IMAP protocol defines its own names for the labels, which must
be set imediately to inform other IMAP clients which may have the
same folder open.  Some labels are translated to the corresponding
IMAP system labels. 

=cut

sub label(@)
{   my $self = shift;
    my $imap = $self->folder->imapClient or return;

    return $imap->getFlag($self->unique, shift)
       if @_ == 1;

    $imap->setFlags($self->unique, @_);
    $self;
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

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
