
use strict;
use warnings;

package Mail::Message::TransferEnc::SevenBit;
use base 'Mail::Message::TransferEnc';

=chapter NAME

Mail::Message::TransferEnc::SevenBit - encode/decode 7bit message bodies

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => '7bit');

=chapter DESCRIPTION

Encode or decode message bodies for 7bit transfer encoding.  This is
only very little encoding.  According to the specs:

RFC-2045 Section 2.7 defines legal `7bit' data:

  "7bit data" refers to data that is all represented as relatively
  short lines with 998 octets or less between CRLF line separation
  sequences [RFC-821].  No octets with decimal values greater than 127
  are allowed and neither are NULs (octets with decimal value 0).  CR
  (decimal value 13) and LF (decimal value 10) octets only occur as
  part of CRLF line separation sequences.

As you can safely conclude: decoding of these bodies is no work
at all.

=chapter METHODS

=cut

sub name() { '7bit' }

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
    {   $changes++ if s/([^\000-\127])/chr(ord($1) & 0x7f)/ge;
        $changes++ if s/[\000\013]//g;

        $changes++ if length > 997;
        push @lines, substr($_, 0, 996, '')."\n"
            while length > 997;

        push @lines, $_;
    }

    unless($changes)
    {   $body->transferEncoding('7bit');
        return $body;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => '7bit'
     , data              => \@lines
     );
}

#------------------------------------------

1;
