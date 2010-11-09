#!/usr/bin/env perl
#
# Encoding and Decoding of 8bit
#

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More tests => 6;

use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::EightBit;

my $decoded = <<DECODED;
yefoiuhéòsjhkw284ÊÈÓUe\000iouoi\013wei
sdfulÓÈËäjlkjliua\000aba
DECODED

my $encoded = <<ENCODED;
yefoiuhéòsjhkw284ÊÈÓUeiouoiwei
sdfulÓÈËäjlkjliuaaba
ENCODED

my $codec = Mail::Message::TransferEnc::EightBit->new;
ok(defined $codec);
is($codec->name, '8bit');

# Test encoding

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , data      => $decoded
  );

my $enc    = $codec->encode($body);
ok($body!=$enc);
is($enc->mimeType, 'text/html');
is($enc->transferEncoding, '8bit');
is($enc->string, $encoded);

# Test decoding

