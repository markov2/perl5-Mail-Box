
use strict;
use warnings;

package Mail::Message::TransferEnc::Base64;
use base 'Mail::Message::TransferEnc';

=head1 NAME

Mail::Message::TransferEnc::Base64 - encode/decode base64 message bodies

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(transfer => 'base64');

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

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=cut

#------------------------------------------

=head2 The Encoder

=cut

#------------------------------------------

sub name() { 'base64' }

#------------------------------------------

=head2 Encoding

=cut

#------------------------------------------

sub check($@)
{   my ($self, $body, %args) = @_;
    $body;
}

#------------------------------------------

sub decode($@)
{   my ($self, $body, %args) = @_;

    my $lines
      = $body->isa('Mail::Message::Body::File')
      ? $self->_decode_from_file($body)
      : $self->_decode_from_lines($body);

    unless($lines)
    {   $body->transferEncoding('none');
        return $body;
    }
 
    my $bodytype
      = defined $args{result_type} ? $args{result_type}
      : $body->isBinary            ? 'Mail::Message::Body::File'
      :                              ref $body;

    $bodytype->new
     ( based_on          => $body
     , transfer_encoding => 'none'
     , data              => $lines
     );
}

sub _decode_from_file($)
{   my ($self, $body) = @_;
    local $_;

    my $in = $body->file || return;

    my @unpacked;
    while($_ = $in->getline)
    {   tr|A-Za-z0-9+=/||cd;   # remove non-base64 chars
        next unless length;

        if(length % 4)
        {   $self->log(WARNING => "Base64 line length not padded on 4.");
            return undef;
        }

        s/=+$//;               # remove padding
        tr|A-Za-z0-9+/| -_|;   # convert to uuencoded format
        return unless length;

        push @unpacked, unpack 'u*', $_;
    }
    $in->close;

    join '', @unpacked;
}

sub _decode_from_lines($)
{   my ($self, $body) = @_;
    my @lines = $body->lines;

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
        return unless length;

        push @unpacked, unpack 'u', (chr 32+length($_)*3/4).$_;
    }

    join '', @unpacked;
}

#------------------------------------------

sub encode($@)
{   my ($self, $body, %args) = @_;

    local $_;
    my $in = $body->file || return $body;
    binmode $in, ':raw' if ref $in eq 'GLOB' || $in->can('BINMODE');

    my (@lines, $bytes);

    while(my $read = $in->read($bytes, 57))
    {   for(pack 'u57', $bytes)
        {   s/^.//;
            tr|` -_|AA-Za-z0-9+/|;

            if(my $align = $read % 3)
            {    if($align==1) { s/..$/==/ } else { s/.$/=/ }
            }

            push @lines, $_;
        }
    }

    $in->close;

    my $bodytype = $args{result_type} || ref $body;
    $bodytype->new
     ( based_on          => $body
     , checked           => 1
     , transfer_encoding => 'base64'
     , data              => \@lines
     );
}

#------------------------------------------

1;
