#!/usr/bin/perl -w
#
# Encoding and Decoding quoted-print bodies
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Body::Lines;
use Mail::Message::CoDec::QuotedPrint;

BEGIN { plan tests => 6 }

my $src = <<SRC;
In the source text, there are a few \010\r strange characters,
which \200\201 must become encoded.  There is also a \010== long line, which must be broken into pieces, and
there are = confusing constructions like this one: =0D, which looks
encoded, but is not.
SRC

my $encoded = <<ENCODED;
In the source text, there are a few =08=0D strange characters,
which =80=81 must become encoded.  There is also a =08=3D=3D long line, whic
h must be broken into pieces, and
there are =3D confusing constructions like this one: =3D0D, which looks
encoded, but is not.
ENCODED

my $decoded = <<'DECODED';   # note the quotes!
In the source text, there are a few \010\015 strange characters,
which \200\201 must become encoded.  There is also a \010== long line, whic
h must be broken into pieces, and
there are = confusing constructions like this one: =0D, which looks
encoded, but is not.
DECODED

my $codec = Mail::Message::CoDec::QuotedPrint->new;
ok(defined $codec);
ok($codec->name eq 'quoted-printable');

# Test encoding

my $body   = Mail::Message::Body::Lines->new(data => $src);
my $result = Mail::Message::Body::Lines->new;

my $enc    = $codec->encode($body, $result);
ok($enc->size == $result->size);
ok($enc->string eq $encoded);

# Test decoding

$body   = Mail::Message::Body::Lines->new(data => $encoded);
$result = Mail::Message::Body::Lines->new;

my $dec    = $codec->decode($body, $result);
ok($dec->size==$result->size);
ok($dec->string eq $decoded);
