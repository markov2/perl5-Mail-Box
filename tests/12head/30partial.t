#!/usr/bin/perl -T
#
# Test the removing fields in partial headers.
#

use Test::More;
use strict;
use warnings;

BEGIN {plan tests => 15}

use Mail::Message::Head::Complete;
use Tools;
use IO::Scalar;

my $h = Mail::Message::Head::Complete->build
 ( Subject => 'this is a test'
 , To      => 'you'
 , Top     => 'above'
 , From    => 'me'
 , 'Content-Length' => 12
 , 'Content-Type'   => 'text/plain'
 );  # lines = 6 fields + blank

ok(defined $h);
isa_ok($h, 'Mail::Message::Head::Complete');
isnt(ref($h), 'Mail::Message::Head::Partial');
cmp_ok($h->nrLines, '==', 7);

ok(defined $h->removeFields('to'));
isa_ok($h, 'Mail::Message::Head::Complete');
isa_ok($h, 'Mail::Message::Head::Partial');
cmp_ok($h->nrLines, '==', 6);
ok(defined $h->get('top'));
ok(! defined $h->get('to'));


ok(defined $h->get('Content-Length'));
ok(defined $h->removeFields( qr/^Content-/i ));
isa_ok($h, 'Mail::Message::Head::Partial');
cmp_ok($h->nrLines, '==', 4);
ok(!defined $h->get('Content-Length'));
