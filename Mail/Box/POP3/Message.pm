
use strict;
use warnings;

package Mail::Box::POP3::Message;
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::POP3::Message - one message on a POP3 server

=head1 SYNOPSIS

 my $folder = new Mail::Box::POP3 ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A Mail::Box::POP3::Message represents one message on a POP3 server. Each
message is stored is stored as separate entity on the server, and maybe
temporarily in your program as well.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=default body_type 'Mail::Message::Body::Lines';

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);
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

    my ($head, $newbody) = $self->folder->getHeadAndBody($self);
    $self->head($head) if defined $head;
    $self->body($newbody);
}

#-------------------------------------------

1;
