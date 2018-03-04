# This code is part of distribution Mail-Box.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Mail::Box::Mbox::Message;
use base 'Mail::Box::File::Message';

use strict;
use warnings;

=chapter NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=chapter SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=chapter DESCRIPTION

Maintain one message in an M<Mail::Box::Mbox> folder.

=chapter METHODS

=cut

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);

    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

sub label(@)
{   my $self   = shift;
    $self->loadHead;    # be sure the status fields have been read
    my $return = $self->SUPER::label(@_);
    $return;
}

sub labels(@)
{   my $self   = shift;
    $self->loadHead;    # be sure the status fields have been read
    $self->SUPER::labels(@_);
}

1;
