#!/usr/bin/perl
#
# Encoding and Decoding of 7bit
#

use Test;
use strict;
use warnings;
use lib qw(. t);

use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::SevenBit;
use Tools;

BEGIN { plan tests => 6 }

my $decoded = <<DECODED;
yefoiuhéòsjhkw284ÊÈÓUe\000iouoi\013wei
sdfulÓÈËäjlkjliua\000aba
DECODED

my $encoded = <<ENCODED;
yefoiuhirsjhkw284JHSUeiouoiwei
sdfulSHKdjlkjliuaaba
ENCODED

my $codec = Mail::Message::TransferEnc::SevenBit->new;
ok(defined $codec);
ok($codec->name eq '7bit');

# Test encoding

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , data      => $decoded
  );

my $enc    = $codec->encode($body);
ok($body!=$enc);
ok($enc->type eq 'text/html');
ok($enc->transferEncoding eq '7bit');
ok($enc->string eq $encoded);

# Test decoding

