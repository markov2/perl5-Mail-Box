#!/usr/bin/perl -w
#
# Encoding and Decoding of 7bit
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Body::Lines;
use Mail::Message::CoDec::SevenBit;

BEGIN { plan tests => 4 }

my $decoded = <<DECODED;
yefoiuhéòsjhkw284ÊÈÓUe\000iouoi\013wei
sdfulÓÈËäjlkjliua\000aba
DECODED

my $encoded = <<ENCODED;
yefoiuhirsjhkw284JHSUeiouoiwei
sdfulSHKdjlkjliuaaba
ENCODED

my $codec = Mail::Message::CoDec::SevenBit->new;
ok(defined $codec);
ok($codec->name eq '7bit');

# Test encoding

my $body   = Mail::Message::Body::Lines->new(data => $decoded);
my $result = Mail::Message::Body::Lines->new;

my $enc    = $codec->encode($body, $result);
ok($enc->size == $result->size);
ok($enc->string eq $encoded);

# Test decoding


# no decoding
