#!/usr/bin/perl
#
# Test processing of message bodies which have their content stored
# in an array.  This does not test the reading of the bodies
# from file.
#

use Test;
use strict;
use warnings;

use lib qw(. t);
use Mail::Message::Body::Lines;
use Tools;

use IO::Scalar;

BEGIN {plan tests => 30}

# Test to read a Lines from file.
# Let's fake the file, for simplicity.

my $filedata = <<'SIMULATED_FILE';
This is a file
with five lines, and it
is used to test whether
the reading into a lines body
would work (or not)
SIMULATED_FILE

my $f = IO::Scalar->new(\$filedata);

my $body = Mail::Message::Body::Lines->new(file => $f);
ok($body);
ok($body->string eq $filedata);
ok($body->nrLines==5);
ok($body->size==length $filedata);

my $fakeout;
my $g = IO::Scalar->new(\$fakeout);
$body->print($g);
ok($fakeout eq $filedata);

my @lines = $body->lines;
ok(@lines==5);
my @filedata = split /(?<=\n)/, $filedata;
ok(@filedata==5);
foreach (0..4) { ok($lines[$_] eq $filedata[$_]) }

# Reading data from lines.

$body = Mail::Message::Body::Lines->new(data => [@filedata]);
ok($body);
ok($body->string eq $filedata);
ok($body->nrLines==5);
ok($body->size==length $filedata);

$fakeout = '';
$body->print($g);
ok($fakeout eq $filedata);

@lines = $body->lines;
ok(@lines==5);
foreach (0..4) { ok($lines[$_] eq $filedata[$_]) }

# Test overloading

ok("$body" eq $filedata);
@lines = @$body;
ok(@lines==5);
foreach (0..4) { ok($lines[$_] eq $filedata[$_]) }
