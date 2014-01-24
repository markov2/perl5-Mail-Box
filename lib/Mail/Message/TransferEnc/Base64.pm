
use strict;
use warnings;

package Mail::Message::TransferEnc::Base64;
use base 'Mail::Message::TransferEnc';

use MIME::Base64;

=chapter NAME

Mail::Message::TransferEnc::Base64 - encode/decode base64 message bodies

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'base64');

=chapter DESCRIPTION

Encode or decode message bodies with base64.  The e-mail protocol and
user agents can not handle binary data.  Therefore, binary data -but
even sometimes non-binary data- is encoded into ASCII, this is
transportable.

Base64 re-groups the bits of bytes, and maps them on characters. The
data contains bytes of 8 bits (an I<octet>).  These are repacked into
groups of 6 bits, pointing in an array of characters containing
C<[A-Za-z0-9+/]>.  This way, three data bytes become 4 base64 bytes.
The encoded data will be trailed by C<'='> characters to align on
four bytes.

=chapter METHODS

=cut

sub name() { 'base64' }

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------

=method decode $body, %options

=warning Base64 line length not padded on 4.

While decoding base64 the data in a message body, a string was found which
was not padded into a multiple of four bytes.  This is illegal, and therefore
this data is ignored.

=cut

sub decode($@)
{   my ($self, $body, %args) = @_;

    my $lines = decode_base64($body->string);
    unless($lines)
    {   $body->transferEncoding('none');
        return $body;
    }
 
    my $bodytype
      = defined $args{result_type} ? $args{result_type}
      : $body->isBinary            ? 'Mail::Message::Body::File'
      :                              ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => $lines
     );
}

#------------------------------------------

sub encode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'base64'
     , data              => encode_base64($body->string)
     );
}

#------------------------------------------

1;
