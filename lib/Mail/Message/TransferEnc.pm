
use strict;
use warnings;

package Mail::Message::TransferEnc;
use base 'Mail::Reporter';

=chapter NAME

Mail::Message::TransferEnc - message transfer encoder/decoder

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'base64');

=chapter DESCRIPTION

This class is the base for various encoders and decoders, which are
used during transport of the message.  These packages, and all which are
derived, are invoked by the message's M<Mail::Message::decoded()> and
M<Mail::Message::encode()> methods:

 my $message = $folder->message(3);
 my $decoded_body = $message->decoded;
 my $encoded_body = $message->encode(transfer => 'base64');

The following coders/decoders are currently available:

=over 4

=item * M<Mail::Message::TransferEnc::Base64>

C<base64> for binary information.

=item * M<Mail::Message::TransferEnc::SevenBit>

C<7bit> for plain old ASCII characters only.

=item * M<Mail::Message::TransferEnc::EightBit>

C<8bit> for extended character set data, not encoded.

=item * M<Mail::Message::TransferEnc::QuotedPrint>

C<quoted-printable> encdoded extended character set data.

=back

=chapter METHODS

=cut

my %encoder =
 ( base64 => 'Mail::Message::TransferEnc::Base64'
 , '7bit' => 'Mail::Message::TransferEnc::SevenBit'
 , '8bit' => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 );

#------------------------------------------

=section The Encoder

=method create $type, %options
Create a new coder/decoder based on the required type.

=warning No decoder for transfer encoding $type.
A decoder for the specified type of transfer encoding is not implemented.

=error Decoder for transfer encoding $type does not work: $@
Compiling the required transfer encoding resulted in errors, which means
that the decoder can not be used.

=cut
 
sub create($@)
{   my ($class, $type) = (shift, shift);

    my $encoder = $encoder{lc $type};
    unless($encoder)
    {   $class->new(@_)->log(WARNING => "No decoder for transfer encoding $type.");
        return;
    }

    eval "require $encoder";
    if($@)
    {   $class->new(@_)->log(ERROR =>
            "Decoder for transfer encoding $type does not work:\n$@");
        return;
    }

    $encoder->new(@_);
}

=c_method addTransferEncoder $type, $class
Adds one new encoder to the list known by the Mail::Box suite.  The
$type is found in the message's header in the C<Content-Transfer-Encoding>
field.

=cut

sub addTransferEncoder($$)
{   my ($class, $type, $encoderclass) = @_;
    $encoder{lc $type} = $encoderclass;
    $class;
}

=method name
The name of the encoder.  Case is not significant.
=cut

sub name {shift->notImplemented}

#------------------------------------------
=section Encoding

=method check $body, %options
Check whether the body is correctly encoded.  If so, the body reference is
returned with the C<checked> flag set.  Otherwise, a new object is created
and returned.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the checker decides to return
modified data.  

=cut

sub check($@) {shift->notImplemented}

=method decode $body, %options
Use the encoder to decode the content of $body.  A new body is returned.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the decoder decides to return
modified data.


=cut

sub decode($@) {shift->notImplemented}

=method encode $body, %options
Use the encoder to encode the content of $body.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the decoder decides to return
modified data.

=cut

sub encode($) {shift->notImplemented}

#------------------------------------------
=section Error handling

=cut

1;
