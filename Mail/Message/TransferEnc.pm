
use strict;
use warnings;

package Mail::Message::TransferEnc;
use base 'Mail::Reporter';

=head1 NAME

Mail::Message::TransferEnc - message transfer encoder/decoder

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'base64');

=head1 DESCRIPTION

This class is the base for various encoders and decoders, which are
used during transport of the message.  This packages, and all which are
derived, are invoked by the message's Mail::Message::decoded() and
Mail::Message::encode() methods:

 my $message = $folder->message(3);
 my $decoded_body = $message->decoded;
 my $encoded_body = $message->encode(transfer => 'base64');

The following coders/decoders are currently available:

=over 4

=item * C<base64> via Mail::Message::TransferEnc::Base64

=item * C<7bit> via Mail::Message::TransferEnc::SevenBit

=item * C<8bit> via Mail::Message::TransferEnc::EightBit

=item * C<quoted-printable> via Mail::Message::TransferEnc::QuotedPrint

=back

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

my %encoder =
 ( base64 => 'Mail::Message::TransferEnc::Base64'
 , '7bit' => 'Mail::Message::TransferEnc::SevenBit'
 , '8bit' => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 );

#------------------------------------------

=method new OPTIONS

=cut

#------------------------------------------

=head2 The Encoder

=cut

#------------------------------------------

=method create TYPE, OPTIONS

Create a new coder/decoder based on the required type.

=cut
 
sub create($@)
{   my ($class, $type) = (shift, shift);

    my $encoder = $encoder{lc $type};
    unless($encoder)
    {   $class->new(@_)->log(WARNING => "No decoder for $type");
        return;
    }

    eval "require $encoder";
    if($@)
    {   $class->new(@_)->log(WARNING => "Decoder for $type does not work:\n$@");
        return;
    }

    $encoder->new(@_);
}

#------------------------------------------

=method addTransferEncoder TYPE, CLASS

(Class method)
Adds one new encoder to the list known by the Mail::Box suite.  The
TYPE is found in the message's header in the C<Content-Transfer-Encoding>
field.

=cut

sub addTransferEncoder($$)
{   my ($class, $type, $encoderclass) = @_;
    $encoder{lc $type} = $encoderclass;
    $class;
}

#------------------------------------------

=method name

The name of the encoder.  Case is not significant.

=cut

sub name {shift->notImplemented}

#------------------------------------------

=head2 Encoding

=cut

#------------------------------------------

=method check BODY, OPTIONS

Check whether the body is correctly encoded.  If so, the body reference is
returned with the C<checked> flag set.  Otherwise, a new object is created
and returned.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the checker decides to return
modified data.  

=cut

sub check($@) {shift->notImplemented}

#------------------------------------------

=method decode BODY [, OPTIONS]

Use the encoder to decode the content of BODY.  A new body is returned.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the decoder decides to return
modified data.


=cut

sub decode($@) {shift->notImplemented}

#------------------------------------------

=method encode BODY, OPTIONS

Use the encoder to encode the content of BODY.

=option  result_type  CLASS
=default result_type  <type of source body>

The type of the body to be produced, when the decoder decides to return
modified data.

=cut

sub encode($) {shift->notImplemented}

#------------------------------------------

1;
