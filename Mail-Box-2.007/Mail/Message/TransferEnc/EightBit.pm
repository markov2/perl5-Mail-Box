
use strict;
use warnings;

package Mail::Message::TransferEnc::EightBit;
use base 'Mail::Message::TransferEnc';

our $VERSION = 2.007;

=head1 NAME

Mail::Message::TransferEnc::EightBit - encode/decode 8bit message bodies

=head1 CLASS HIERARCHY

 Mail::Message::TransferEnc::EightBit
 is a Mail::Message::TransferEnc
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => '8bit');

=head1 DESCRIPTION

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

=head1 METHOD INDEX

The general methods for C<Mail::Message::TransferEnc::EightBit> objects:

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

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMT = L<Mail::Message::TransferEnc>

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

This code is beta, version 2.007.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
