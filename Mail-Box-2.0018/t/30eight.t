#!/usr/bin/perl -w
#
# Encoding and Decoding of 8bit
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Body::Lines;
use Mail::Message::TransferEnc::EightBit;
use Tools;

BEGIN { plan tests => 6 }

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
ok($codec->name eq '8bit');

# Test encoding

my $body   = Mail::Message::Body::Lines->new
  ( mime_type => 'text/html'
  , data      => $decoded
  );

my $enc    = $codec->encode($body);
ok($body!=$enc);
ok($enc->type eq 'text/html');
ok($enc->transferEncoding eq '8bit');
ok($enc->string eq $encoded);

# Test decoding

