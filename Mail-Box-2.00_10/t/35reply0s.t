#!/usr/bin/perl -w
#
# Test stripping signatures
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Construct;

BEGIN {plan tests => 21}

#
# No strip possible
#

my @lines = qw/1 2 3 4 5/;
my $sig   = Mail::Message->stripSignature(\@lines);
ok(@lines==5);
ok(defined $sig);
ok(@$sig ==0);

#
# Simple strip
#

@lines = ('a', 'b', '--', 'sig');
$sig   = Mail::Message->stripSignature(\@lines);
ok(@lines==2);
ok($lines[0] eq 'a');
ok($lines[1] eq 'b');

ok(@$sig == 2);
ok($sig->[0] eq '--');
ok($sig->[1] eq 'sig');

#
# Try signature too large
#

@lines = qw/1 2 3 -- 4 5 6 7 8 9 10/;
$sig   = Mail::Message->stripSignature(\@lines, max_lines => 7);
ok(@$sig == 0);
ok(@lines==11);

$sig   = Mail::Message->stripSignature(\@lines, max_lines => 8);
ok(@$sig == 8);
ok(@lines== 3);

#
# Try whole body is signature
#

@lines = qw/-- 1 2 3 4/;
$sig   = Mail::Message->stripSignature(\@lines);
ok(@$sig == 5);
ok(@lines== 0);

#
# Try string to find sep
#

@lines = qw/1 2 3 abc 4 5 6/;
$sig   = Mail::Message->stripSignature(\@lines, pattern => 'b');
ok(@$sig == 0);

$sig   = Mail::Message->stripSignature(\@lines, pattern => 'a');
ok(@$sig == 4);

#
# Try regexp to find sep
#

@lines = qw/1 2 3 abba baab 4 5 6/;
$sig   = Mail::Message->stripSignature(\@lines, pattern => qr/b{2}/);
ok(@$sig == 5);
ok(@lines== 3);

#
# Try code to find sep
#

@lines = qw/1 2 3 ab 4 5 6/;
$sig   = Mail::Message->stripSignature(\@lines, pattern => sub {$_[0] eq 'ab'});
ok(@$sig == 4);
ok(@lines== 3);

