
use strict;
use warnings;

package Mail::Message::TransferEnc::Binary;
use base 'Mail::Message::TransferEnc';

=head1 NAME

Mail::Message::TransferEnc::Binary - encode/decode binary message bodies

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'binary');

=head1 DESCRIPTION

Encode or decode message bodies for binary transfer encoding.  This is
totally no encoding.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=item new OPTIONS

=cut

#------------------------------------------

=head2 The Encoder

=cut

#------------------------------------------

sub name() { 'binary' }

#------------------------------------------

=head2 Encoding

=cut

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------

sub decode($@)
{   my ($self, $body, %args) = @_;
    $body->transferEncoding('none');
    $body;
}

#------------------------------------------

sub encode($@)
{   my ($self, $body, %args) = @_;

    my @lines;

    my $changes = 0;
    foreach ($self->lines)
    {   $changes++ if s/[\000\013]//g;
        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('none');
        return $body;
    }

    my $bodytype = $args{result_type} || ref($self->load);

    $bodytype->new
     ( based_on          => $self
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

#------------------------------------------

1;
