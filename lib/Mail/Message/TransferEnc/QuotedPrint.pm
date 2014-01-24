
use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
use base 'Mail::Message::TransferEnc';

use MIME::QuotedPrint;

=chapter NAME

Mail::Message::TransferEnc::QuotedPrint - handle quoted-printable message bodies

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'quoted-printable');

=chapter DESCRIPTION

Encode and decode message bodies for quoted-printable transfer encoding.
The Quoted-Printable encoding is intended
to represent data that largely consists of bytes that correspond to
printable characters in the ASCII character set.  Non-printable
characters (as defined by English Americans) are represented by a
triplet consisting of the character "=" followed by two hexadecimal
digits.

=chapter METHODS

=cut

sub name() { 'quoted-printable' }

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

=method decode $body, %options
Decoding is tricky, and not without loss of information.  Lines will
stay separate lines, although they might have been joined before the
encoding split them up.  Characters which are not printable will be
replaced by their octal value, and carriage returns (C<'=0D'>) at
end of line are removed.
=cut

sub decode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => decode_qp($body->string)
     );
}

=method encode $body, %options
Encoding is to quoted-printable is a careful process: All characters
outside the normal printing range, and including C<'='> are encoded.
They are translated into a C<'='> followed by a two digit hex of the
ascii value of the character.  The same treatment is for white-spaces
at the end of a line.

The lines which are constructed which must be 76 characters max, not
broken on encoded characters.
=cut

sub encode($@)
{   my ($self, $body, %args) = @_;

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'quoted-printable'
     , data              => encode_qp($body->string)
     );
}

1;
