
use strict;
use warnings;

package Mail::Message::CoDec::Binary;
use base 'Mail::Message::CoDec';

our $VERSION = '2.00_10';

=head1 NAME

 Mail::Message::CoDec::Binary - Encode/Decode binary message bodies

=head1 CLASS HIERARCHY

 Mail::Message::CoDec::Binary
 is a Mail::Message::CoDec
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode('binary');

=head1 DESCRIPTION

Encode or decode message bodies for binary transfer encoding.  This is
totally no encoding.

=head1 METHOD INDEX

The general methods for C<Mail::Message::CoDec::Binary> objects:

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

sub name() { 'binary' }

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
    foreach ($self->lines)
    {   $changes++ if s/[\000\013]//g;
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

=head1 VERSION

This code is beta, version 2.00_10.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
