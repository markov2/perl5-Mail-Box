
use strict;
use warnings;

package Mail::Message::CoDec::SevenBit;
use base 'Mail::Message::CoDec';

our $VERSION = '2.00_09';

=head1 NAME

 Mail::Message::CoDec::SevenBit - Encode/Decode 7bit message bodies

=head1 CLASS HIERARCHY

 Mail::Message::CoDec::Base64
 is a Mail::Message::CoDec
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode('7bit');

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

The general methods for C<Mail::Message::CoDec::Base64> objects:

  MMC create TYPE, OPTIONS                 new OPTIONS
  MMC decode BODY, RESULT-BODY          MR report [LEVEL]
  MMC encode BODY, RESULT-BODY          MR reportAll [LEVEL]
   MR errors                            MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

  MMC addCoDec TYPE, CLASS              MR logSettings
   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMC = L<Mail::Message::CoDec>

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

sub decode($$)
{   my ($self, $from, $to) = @_;
    $from;
}

#------------------------------------------

sub encode($$)
{   my ($self, $from, $to) = @_;

    my @lines;
    my $changes = 0;

    foreach ($from->lines)
    {   $changes++ if s/[^\000-\127]/chr(ord($&) & 0x7f)/ge;
        $changes++ if s/[\000\013]//g;

        $changes++ if length > 997;
        push @lines, substr($_, 0, 996, '')."\n"
            while length > 997;

        push @lines, $_;
    }

    return $from unless $changes;
    $to->data(\@lines);
    $to;
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

This is a reimplementation of the algorithm used in C<MIME::Base64>,
designed by Gisle Aas.

=head1 VERSION

This code is beta, version 2.00_09.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
