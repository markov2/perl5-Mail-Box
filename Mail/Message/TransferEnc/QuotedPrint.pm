
use strict;
use warnings;

package Mail::Message::TransferEnc::QuotedPrint;
use base 'Mail::Message::TransferEnc';

=head1 NAME

Mail::Message::TransferEnc::QuotedPrint - handle quoted-printable message bodies

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'quoted-printable');

=head1 DESCRIPTION

Encode and decode message bodies for quoted-printable transfer encoding.
The Quoted-Printable encoding is intended
to represent data that largely consists of bytes that correspond to
printable characters in the ASCII character set.  Non-printable
characters (as defined by English Americans) are represented by a
triplet consisting of the character "=" followed by two hexadecimal
digits.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

=cut

#------------------------------------------

=head2 The Encoder

=cut

#------------------------------------------

sub name() { 'quoted-printable' }

#------------------------------------------

=head2 Encoding

=cut

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------

=item decode BODY, OPTIONS

Decoding is tricky, and not without loss of information.  Lines will
stay separate lines, although they might have been joined before the
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
              $code == 9  ? "\t"
            : $code < 040 ? sprintf('\\%03o', $code)
            : chr $code
         /ge;

        $_ .= "\n" unless s/\=$//;
        push @lines, $_;
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => \@lines
     );
}

#------------------------------------------

=item encode BODY, OPTIONS

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
                $part   = substr $line, 0, $maxline;
                my $all = (length $part==length $line);
                for($part)
                {   $changes  = tr/ \t!-<>-~]//c;
                    $changes += 1 if $all && m/[ \t]$/;
                }
                last if length($part) + $changes*2 + ($all ? 0 : 1) <= 76;
                $maxline--;
            }

            substr $line, 0, $maxline, '';

            for($part)
            {   s/[^ \t!-<>-~]/sprintf '=%02X', ord $&/ge;
                s/[ \t]$/ join '', map {sprintf '=%02X', ord $_} $&/gem;
            }

            push @lines, $part . (length($line) ? '=' : '') .  "\n";
        }
    }

    my $bodytype = $args{result_type} || ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'quoted-printable'
     , data              => \@lines
     );
}

#------------------------------------------

1;
