
use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
use base 'Mail::Message::TransferEnc';

our $VERSION = 2.00_17;

=head1 NAME

Mail::Message::TransferEnc::QuotedPrint - Handle quoted-printable message bodies

=head1 CLASS HIERARCHY

 Mail::Message::TransferEnc::QuotedPrint
 is a Mail::Message::TransferEnc
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'quoted-printable');

=head1 DESCRIPTION

Encode and decode message bodies for quoted-printable transfer encoding.
The Quoted-Printable encoding is intended
to represent data that largely consists of bytes that correspond to
printable characters in the ASCII character set.  Non-printable
characters (as defined by english americans) are represented by a
triplet consisting of the character "=" followed by two hexadecimal
digits.

=head1 METHOD INDEX

The general methods for C<Mail::Message::TransferEnc::QuotedPrint> objects:

  MMT check BODY [, OPTIONS]           MMT name
  MMT create TYPE, OPTIONS                 new OPTIONS
      decode BODY                       MR report [LEVEL]
      encode                            MR reportAll [LEVEL]
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

sub name() { 'quoted-printable' }

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body->checked(1);
    $body;
}

#------------------------------------------

=item decode BODY

Decoding is tricky, and not without loss of information.  Lines will
stay seperate lines, although they might have been joined before the
encoding split them up.  Characters which are not printable will be
replaced by their octal value, and carriage returns (C<'=0D'>) at
end of line are removed.

=cut

sub decode($@)
{   my ($self, $body, %args) = @_;

    my @lines;
    foreach ($body->lines)
    {   s/\s+$//;
        s/=0[dD]$//;
        s/\=([A-Fa-f0-9]{2})/
            my $code = hex $1;
            $code < 040 || $code > 127 ? sprintf('\\%03o', $code) : chr $code
         /ge;

        push @lines, "$_\n";
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

#------------------------------------------

=item encode

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

    my @lines;

    # All special characters and whitespace at end of line must be
    # encoded into lines shorter than 76 chars.

    foreach my $line ($body->lines)
    {   chomp $line;
        while(length $line)
        {   my $maxline = 76;
            my $part;

            while(1)
            {   my $changes;
                $part = substr $line, 0, $maxline;
                for($part)
                {   $changes  = tr/ \t\n!-<>-~]//c;
                    $changes += length $1 if m/(\s+)$/;
                }
                last if length($part) + $changes*2 <= 76;
                $maxline--;
            }

            substr $line, 0, $maxline, '';

            for($part)
            {   s/[^ \t\n!-<>-~]/sprintf '=%02X', ord $&/ge;
                s/\s+$/ join '', map {sprintf '=%02X', ord $_} $&/gem;
            }

            push @lines, "$part\n";
        }
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'quoted-printable'
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

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
