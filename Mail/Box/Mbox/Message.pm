
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

=section Labels

=cut

sub label(@)
{   my $self   = shift;
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

#-------------------------------------------

=method labelsToStatus

When the labels were changed, that may effect the C<Status> and/or
C<X-Status> header lines of mbox messages.  Read about the relation
between these fields and the labels in the DETAILS chapter.

The method will carefully only affect the result of M<modified()> when
there is a real change of flags, so not for each call to M<label()>.

=cut

sub labelsToStatus()
{   my $self    = shift;
    my $head    = $self->head;
    my $labels  = $self->labels;

    my $status  = $head->get('status') || '';
    my $newstatus
      = $labels->{seen}    ? 'RO'
      : $labels->{old}     ? 'O'
      : '';

    $head->set(Status => $newstatus)
        if $newstatus ne $status;

    my $xstatus = $head->get('x-status') || '';
    my $newxstatus
      = ($labels->{replied} ? 'A' : '')
      . ($labels->{flagged} ? 'F' : '');

    $head->set('X-Status' => $newxstatus)
        if $newxstatus ne $xstatus;

    $self;
}

#-------------------------------------------

=method statusToLabels

Update the labels according the status lines in the header.  See the
description in the DETAILS chapter.

=cut

sub statusToLabels()
{   my $self    = shift;
    my $head    = $self->head;

    if(my $status  = $head->get('status'))
    {   $self->{MM_labels}{seen} = ($status  =~ /R/ ? 1 : 0);
        $self->{MM_labels}{old}  = ($status  =~ /O/ ? 1 : 0);
    }

    if(my $xstatus = $head->get('x-status'))
    {   $self->{MM_labels}{replied} = ($xstatus  =~ /A/ ? 1 : 0);
        $self->{MM_labels}{flagged} = ($xstatus  =~ /F/ ? 1 : 0);
    }

    $self;
}

#------------------------------------------

=chapter DETAILS

=section Labels

=subsection Status and X-Status fields

Mbox folders have no special means of storing information about messages
(except the message separator line), and therefore have to revert to
adding fields to the message header when something special comes up.

Most applications which can handle mbox folders support the C<Status> and
C<X-Status> field convensions which are implemented by M<Mail::Box::Mbox>.
The following encoding is used:

 Flag   Field       Label
 R      Status   => seen    (Read)
 O      Status   => old     (not recent)
 A      X-Status => replied (Answered)
 F      X-Status => flagged

There is no special flag for C<deleted>, which most other folders support:
messages flagged to be deleted will never be written to a folder file when
it is closed.

=cut

#------------------------------------------

1;
