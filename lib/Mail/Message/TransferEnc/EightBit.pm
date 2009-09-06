
use strict;
use warnings;

package Mail::Message::TransferEnc::EightBit;
use base 'Mail::Message::TransferEnc';

=chapter NAME

Mail::Message::TransferEnc::EightBit - encode/decode 8bit message bodies

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => '8bit');

=chapter DESCRIPTION

Encode or decode message bodies for 8bit transfer encoding.  This is
only very little encoding.  According to the specs:

RFC-2045 Section 2.8 defines legal `8bit' data:

 "8bit data" refers to data that is all represented as relatively
 short lines with 998 octets or less between CRLF line separation
 sequences [RFC-821]), but octets with decimal values greater than 127
 may be used.  As with "7bit data" CR and LF octets only occur as part
 of CRLF line separation sequences and no NULs are allowed.

As you can safely conclude: decoding of these bodies is no work
at all.

=chapter METHODS

=cut

sub name() { '8bit' }

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

    foreach ($body->lines)
    {   $changes++ if s/[\000\013]//g;

        # there shouldn't be any NL inside a line.
        $changes++ if length > 997;
        push @lines, substr($_, 0, 996, '')."\n"
            while length > 997;

        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('8bit');
        return $body;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => '8bit'
     , data              => \@lines
     );
}

#------------------------------------------

1;
