#!/usr/bin/perl
#
# Test processing of message bodies which have their content stored
# in an array.  This does not test the reading of the bodies
# from file.
#

use Test::More;
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
is($body->string, $filedata);
cmp_ok($body->nrLines, "==", 5);
cmp_ok($body->size, "==", length $filedata);

my $fakeout;
my $g = IO::Scalar->new(\$fakeout);
$body->print($g);
is($fakeout, $filedata);

my @lines = $body->lines;
cmp_ok(@lines, "==", 5);
my @filedata = split /^/, $filedata;
cmp_ok(@filedata, "==", 5);
foreach (0..4) { is($lines[$_], $filedata[$_]) }

# Reading data from lines.

$body = Mail::Message::Body::Lines->new(data => [@filedata]);
ok($body);
is($body->string, $filedata);
cmp_ok($body->nrLines, "==", 5);
cmp_ok($body->size, "==", length $filedata);

$fakeout = '';
$body->print($g);
is($fakeout, $filedata);

@lines = $body->lines;
cmp_ok(@lines, "==", 5);
foreach (0..4) { is($lines[$_], $filedata[$_]) }

# Test overloading

is("$body", $filedata);
@lines = @$body;
cmp_ok(@lines, "==", 5);
foreach (0..4) { is($lines[$_], $filedata[$_]) }
