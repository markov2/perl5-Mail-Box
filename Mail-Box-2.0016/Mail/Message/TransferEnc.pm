
use strict;
use warnings;

package Mail::Message::TransferEnc;
use base 'Mail::Reporter';

our $VERSION = 2.00_16;

=head1 NAME

Mail::Message::TransferEnc - Message transfer encoder/decoder

=head1 CLASS HIERARCHY

 Mail::Message::TransferEnc
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'base64');

=head1 DESCRIPTION

This class is the base for various encoders and decoders, which are
used during transport of the message.  This packages, and all which are
derived, are invoked by the message's C<decoded()> and C<encode> methods:

 my $message = $folder->message(3);
 my $decoded_body = $message->decoded;
 my $encoded_body = $message->encode(transfer => 'base64');

The following coders/decoders are currently available:

=over 4

=item * base64 via C<Mail::Message::TransferEnc::Base64>

=item * 7bit via C<Mail::Message::TransferEnc::SevenBit>

=item * 8bit via C<Mail::Message::TransferEnc::EightBit>

=item * quoted-printable via C<Mail::Message::TransferEnc::QuotedPrint>

=back

=head1 METHOD INDEX

The general methods for C<Mail::Message::TransferEnc> objects:

      check BODY [, OPTIONS]               name
      create TYPE, OPTIONS                 new OPTIONS
      decode BODY [, OPTIONS]           MR report [LEVEL]
      encode BODY [, OPTIONS]           MR reportAll [LEVEL]
   MR errors                            MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
      addTransferEncoder TYPE, CLASS    MR logSettings

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

my %encoder =
 ( base64 => 'Mail::Message::TransferEnc::Base64'
 , '7bit' => 'Mail::Message::TransferEnc::SevenBit'
 , '8bit' => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 );

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN          DEFAULT
 log               Mail::Reporter        'WARNINGS'
 trace             Mail::Reporter        'WARNINGS'

=cut

#------------------------------------------

=item create TYPE, OPTIONS

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

=item name

The name of the encoder.  Case is not significant.

=cut

sub name {shift->notImplemented}

#------------------------------------------

=item check BODY [, OPTIONS]

Check whether the body is correctly encoded.  If so, the body reference is
returned with the C<checked> flag set.  Otherwise, a new object is created
and returned.

 OPTION       DESCRIBED_IN                DEFAULT
 result_type  Mail::Message::TransferEnc  <type of source body>

=cut

sub check($@) {shift->notImplemented}

#------------------------------------------

=item decode BODY [, OPTIONS]

Use the encoder to decode the content of BODY.  A new body is returned.

 OPTION       DESCRIBED_IN                DEFAULT
 result_type  Mail::Message::TransferEnc  <type of source body>

=cut

sub decode($@) {shift->notImplemented}

#------------------------------------------

=item encode BODY [, OPTIONS]

Use the encoder to encode the content of BODY.  A new body is returned.

=cut

sub encode($) {shift->notImplemented}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item addTransferEncoder TYPE, CLASS

(Class method)
Adds one new encoder to the list known by the C<Mail::Box> suite.  The
TYPE is found in the message's header in the C<Content-Transfer-Encoding>
field.

=cut

sub addTransferEncoder($$)
{   my ($class, $type, $encoderclass) = @_;
    $encoder{lc $type} = $encoderclass;
    $class;
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_16.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
