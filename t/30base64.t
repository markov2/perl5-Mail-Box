#!/usr/bin/perl
#
# Encoding and Decoding of Base64
# Could use some more tests....
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::Base64;
use Tools;

warn "   * Transfer Encodings status BETA\n";

BEGIN { plan tests => 11 }

my $decoded = <<DECODED;
This text is used to test base64 encoding and decoding.  Let
see whether it works.
DECODED

my $encoded = <<ENCODED;
VGhpcyB0ZXh0IGlzIHVzZWQgdG8gdGVzdCBiYXNlNjQgZW5jb2RpbmcgYW5kIGRlY29kaW5nLiAg
TGV0CnNlZSB3aGV0aGVyIGl0IHdvcmtzLgo=
ENCODED

my $codec = Mail::Message::TransferEnc::Base64->new;
ok(defined $codec);
ok($codec->name eq 'base64');

# Test encoding

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , data      => $decoded
  );

ok($body->mimeType eq 'text/html');

my $enc    = $codec->encode($body);
ok($body!=$enc);
ok($enc->mimeType eq 'text/html');
ok($enc->transferEncoding eq 'base64');
ok($enc->string eq $encoded);

# Test decoding

$body   = Mail::Message::Body::Lines->new
  ( transfer_encoding => 'base64'
  , mime_type         => 'text/html'
  , data              => $encoded
  );

my $dec = $codec->decode($body);
ok($dec!=$body);
ok($enc->mimeType eq 'text/html');
ok($dec->transferEncoding eq 'none');
ok($dec->string eq $decoded);

