
use strict;
use warnings;

package Mail::Message::CoDec;
use base 'Mail::Reporter';

our $VERSION = '2.00_10';

=head1 NAME

 Mail::Message::CoDec - Message encoder/decoder

=head1 CLASS HIERARCHY

 Mail::Message::CoDec
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode('base64');

=head1 DESCRIPTION

This class is the base for various message encoders and decoders, which
can be used to translate message bodies into readable strings.  The
decoder is automatically invoked when a coded message body is read
from file.

The following coders/decoders are currently available:

=over 4

=item * base64 via C<Mail::Message::CoDec::Base64>

=item * 7bit via C<Mail::Message::CoDec::SevenBit>

=item * 8bit via C<Mail::Message::CoDec::EightBit>

=item * quoted-printable via C<Mail::Message::CoDec::QuotedPrint>

=back

=head1 METHOD INDEX

The general methods for C<Mail::Message::CoDec> objects:

      create TYPE, OPTIONS                 name
      decode BODY, RESULT-BODY             new OPTIONS
      encode BODY, RESULT-BODY          MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR DESTROY                           MR logPriority LEVEL
      addCoDec TYPE, CLASS              MR logSettings
   MR inGlobalDestruction               MR notImplemented

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

my %codec =
 ( base64 => 'Mail::Message::CoDec::Base64'
 , '7bit' => 'Mail::Message::CoDec::SevenBit'
 , '8bit' => 'Mail::Message::CoDec::EightBit'
 , 'quoted-printable' => 'Mail::Message::CoDec::QuotedPrint'
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

    my $codec = $codec{lc $type};
    unless($codec)
    {   $class->new(@_)->log(WARNING => "No decoder for $type");
        return;
    }

    eval "require $codec";
    if($@)
    {   $class->new(@_)->log(WARNING => "Decoder for $type does not work:\n$@");
        return;
    }

    $codec->new(@_);
}

#------------------------------------------

=item name

The name of the codec.  Case is not significant.

=cut

sub name {shift->notImplemented}

#------------------------------------------

=item decode BODY, RESULT-BODY

Use the codec to decode the content of BODY into a new RESULT-BODY object.
Both are instances of C<Mail::Message::Body> objects.  The latter object
is returned.

=cut

sub decode($) {shift->notImplemented}

#------------------------------------------

=item encode BODY, RESULT-BODY

Use the codec to encode the content of BODY into a new RESULT-BODY object.
Both are instances of C<Mail::Message::Body> objects.  The latter object
is returned.

=cut

sub encode($) {shift->notImplemented}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item addCoDec TYPE, CLASS

(Class method)
Adds one new codec to the list known by the C<Mail::Box> suite.  The
TYPE is found in the message's header in the C<Content-Transfer-Encoding>
field.

=cut

sub addCoDec($$)
{   my ($class, $type, $codecclass) = @_;
    $codec{lc $type} = $codecclass;
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

This code is beta, version 2.00_10.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
