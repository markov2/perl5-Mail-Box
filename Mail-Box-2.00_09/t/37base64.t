#!/usr/bin/perl -w
#
# Encoding and Decoding of Base64
# Could use some more tests....
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Body::Lines;
use Mail::Message::CoDec::Base64;

BEGIN { plan tests => 6 }

my $decoded = <<DECODED;
This text is used to test base64 encoding and decoding.  Let
see whether it works.
DECODED

my $encoded = <<ENCODED;
VGhpcyB0ZXh0IGlzIHVzZWQgdG8gdGVzdCBiYXNlNjQgZW5jb2RpbmcgYW5kIGRlY29kaW5nLiAg
TGV0CnNlZSB3aGV0aGVyIGl0IHdvcmtzLgo=
ENCODED

my $codec = Mail::Message::CoDec::Base64->new;
ok(defined $codec);
ok($codec->name eq 'Base64');

# Test encoding

my $body   = Mail::Message::Body::Lines->new(data => $decoded);
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

