
use strict;
use warnings;

package Mail::Message::TransferEnc::SevenBit;
use base 'Mail::Message::TransferEnc';

our $VERSION = 2.012;

=head1 NAME

Mail::Message::TransferEnc::SevenBit - encode/decode 7bit message bodies

=head1 CLASS HIERARCHY

 Mail::Message::TransferEnc::SevenBit
 is a Mail::Message::TransferEnc
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => '7bit');

=head1 DESCRIPTION

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

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::TransferEnc> (MMT).

The general methods for C<Mail::Message::TransferEnc::SevenBit> objects:

  MMT check BODY [, OPTIONS]           MMT name
  MMT create TYPE, OPTIONS                 new OPTIONS
  MMT decode BODY [, OPTIONS]           MR report [LEVEL]
  MMT encode BODY [, OPTIONS]           MR reportAll [LEVEL]
   MR errors                            MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
  MMT addTransferEncoder TYPE, CLASS    MR logSettings

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN          DEFAULT
 log               Mail::Reporter        'WARNINGS'
 trace             Mail::Reporter        'WARNINGS'

=cut

#------------------------------------------

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
    {   $changes++ if s/[^\000-\127]/chr(ord($&) & 0x7f)/ge;
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

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.012.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
