
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::File::Message';

=chapter NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=chapter SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=chapter DESCRIPTION

Maintain one message in an M<Mail::Box::Mbox> folder.

=chapter METHODS

=cut

#-------------------------------------------

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);

    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

1;
