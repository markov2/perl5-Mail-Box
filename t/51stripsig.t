#!/usr/bin/perl
#
# Test stripping signatures
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Mail::Message::Body::Construct;
use Mail::Message::Body;
use Tools;

BEGIN {plan tests => 37}
warn "   * Message construction status: released\n";

#
# No strip possible
#

my @lines = map { "$_\n" } qw/1 2 3 4 5/;
my $body  = Mail::Message::Body::Lines->new(data => \@lines);

my ($stripped, $sig) = $body->stripSignature;
ok($stripped==$body);
ok(!defined $sig);
ok($stripped->nrLines==@lines);

my $stripped2 = $body->stripSignature;
ok($stripped2==$body);

#
# Simple strip
#

@lines = map { "$_\n" } qw(a b -- sig);
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature;
ok($stripped!=$body);
ok($sig!=$body);

ok($stripped->nrLines==2);
my @stripped_lines = $stripped->lines;
ok(@stripped_lines==2);
ok($stripped_lines[0] eq $lines[0]);
ok($stripped_lines[1] eq $lines[1]);

ok($sig->nrLines==2);
my @sig_lines = $sig->lines;
ok(@sig_lines==2);
ok($sig_lines[0] eq $lines[2]);
ok($sig_lines[1] eq $lines[3]);

#
# Try signature too large
#

@lines = map { "$_\n" } qw/1 2 3 -- 4 5 6 7 8 9 10/;
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature(max_lines => 7);
ok(!defined $sig);
ok($stripped->nrLines==11);

($stripped, $sig) = $body->stripSignature(max_lines => 8);
ok($sig->nrLines==8);
@sig_lines = $sig->lines;
ok(@sig_lines==8);
ok($sig_lines[0] eq $lines[3]);
ok($sig_lines[1] eq $lines[4]);
ok($sig_lines[-1] eq $lines[-1]);

ok($stripped->nrLines==3);
@stripped_lines = $stripped->lines;
ok(@stripped_lines==3);
ok($stripped_lines[0] eq $lines[0]);
ok($stripped_lines[1] eq $lines[1]);
ok($stripped_lines[2] eq $lines[2]);

#
# Try whole body is signature
#

@lines = map { "$_\n" } qw/-- 1 2 3 4/;
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature(max_lines => 7);
ok($sig->nrLines == 5);
ok(defined $stripped);
ok($stripped->nrLines == 0);

#
# Try string to find sep
#

@lines = map { "$_\n" } qw/1 2 3 abc 4 5 6/;
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature(pattern => 'b');
ok(!defined $sig);

($stripped, $sig) = $body->stripSignature(pattern => 'a');
ok($sig->nrLines == 4);

#
# Try regexp to find sep
#

@lines = map { "$_\n" } qw/1 2 3 abba baab 4 5 6/;
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature(pattern => qr/b{2}/);
ok($sig);
ok($sig->nrLines == 5);
ok($stripped->nrLines == 3);

#
# Try code to find sep
#

@lines = map { "$_\n" } qw/1 2 3 ab 4 5 6/;
$body  = Mail::Message::Body::Lines->new(data => \@lines);
($stripped, $sig) = $body->stripSignature(pattern => sub {$_[0] eq "ab\n"});
ok($sig);
ok($sig->nrLines == 4);
ok($stripped->nrLines == 3);

