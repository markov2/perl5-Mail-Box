#!/usr/bin/perl
#
# Test processing of message bodies which have their content stored
# in a file.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);
use Mail::Message::Body::File;
use Tools;

use IO::Scalar;

BEGIN {plan tests => 32}

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

my $body = Mail::Message::Body::File->new(file => $f);
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
my @filedata = split /(?<=\n)/, $filedata;
cmp_ok(@filedata, "==", 5);
foreach (0..4) { is($lines[$_], $filedata[$_]) }

# Reading data from lines.

$body = Mail::Message::Body::File->new(data => [@filedata]);
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

# Test cleanup

my $filename = $body->tempFilename;
ok(-f $filename);
undef $body;
ok(! -f $filename);

