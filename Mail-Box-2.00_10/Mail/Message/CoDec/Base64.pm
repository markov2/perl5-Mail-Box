
use strict;
use warnings;

package Mail::Message::CoDec::Base64;
use base 'Mail::Message::CoDec';

our $VERSION = '2.00_10';

=head1 NAME

 Mail::Message::CoDec::Base64 - Encode/Decode Base64 message bodies

=head1 CLASS HIERARCHY

 Mail::Message::CoDec::Base64
 is a Mail::Message::CoDec
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode('base64');

=head1 DESCRIPTION

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

=head1 METHOD INDEX

The general methods for C<Mail::Message::CoDec::Base64> objects:

  MMC create TYPE, OPTIONS             MMC name
  MMC decode BODY, RESULT-BODY             new OPTIONS
  MMC encode BODY, RESULT-BODY          MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR DESTROY                           MR logPriority LEVEL
  MMC addCoDec TYPE, CLASS              MR logSettings
   MR inGlobalDestruction               MR notImplemented

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

sub name() { 'Base64' }

#------------------------------------------

sub decode($$)
{   my ($self, $from, $to) = @_;
    my $data
      = $from->isa('Mail::Message::Body::File')
      ? $self->_decode_from_file($from, $to)
      : $self->_decode_from_lines($from, $to);

    return $from unless $data;
    $to->data($data);
    $to;
}

sub _decode_from_file($$)
{   my ($self, $from, $to) = @_;
    local $_;

    my $in = $from->file || return;

    my @unpacked;
    while($in->getline)
    {   tr|A-Za-z0-9+=/||cd;   # remove non-base64 chars
        next unless length;

        if(length % 4)
        {   $self->log(WARNING => "Base64 line length not padded on 4.");
            return undef;
        }

        s/=+$//;               # remove padding
        tr|A-Za-z0-9+/| -_|;   # convert to uuencoded format
        push @unpacked, unpack 'u*', $_;
    }
    $in->close;

    join '', @unpacked;
}

sub _decode_from_lines($$)
{   my ($self, $from, $to) = @_;
    my @lines = $from->lines;

    my @unpacked;
    foreach (@lines)
    {   tr|A-Za-z0-9+=/||cd;   # remove non-base64 chars
        next unless length;

        unless(length % 4)
        {   $self->log(WARNING => "Base64 line length not padded on 4.");
            return undef;
        }

        s/=+$//;               # remove padding
        tr|A-Za-z0-9+/| -_|;   # convert to uuencoded format
        push @unpacked, unpack 'u', (chr 32+length($_)*3/4).$_;
    }

    join '', @unpacked;
}

#------------------------------------------

sub encode($$)
{   my ($self, $from, $to) = @_;
    local $_;

    my $in = $from->file || return $from;

    my (@lines, $bytes);

    while(my $read = $in->read($bytes, 57))
    {   for(pack 'u57', $bytes)
        {   chop;
            s/^.//;
            tr|` -_|AA-Za-z0-9+/|s;

            if(my $align = $read % 3)
            {    if($align==1) { s/..$/==/ } else { s/.$/=/ }
            }

            push @lines, "$_\n";
        }
    }

    $in->close;

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

=head1 VERSION

This code is beta, version 2.00_10.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
