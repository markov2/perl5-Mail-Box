#!/usr/bin/perl -T
#
# Test reporting warnings, errors and family.
#

use Test::More;

use strict;
use warnings;

use Mail::Reporter;
use Tools;

BEGIN {plan tests => 85}

#
# Dualvar logPriority
#

my $a = Mail::Reporter->logPriority('WARNING');
ok(defined $a);
ok($a == 4);
is($a, 'WARNING');

my $b = Mail::Reporter->logPriority('WARNINGS');
ok(defined $b);
ok($b == 4);
is($b, 'WARNING');

my $c = Mail::Reporter->logPriority(4);
ok(defined $c);
ok($c == 4);
is($c, 'WARNING');

my $d = Mail::Reporter->logPriority('AAP');
ok(!defined $d);
my $e = Mail::Reporter->logPriority(8);
ok(!defined $e);

#
# Set default trace
#

my ($l, $t) = Mail::Reporter->defaultTrace('DEBUG', 'ERRORS');
ok(defined $l);
ok(defined $t);

is($l, 'DEBUG',                     'string log level');
cmp_ok($l, '==',  1,                'numeric log level');

is($t, 'ERROR',                     'string trace level');
cmp_ok($t, '==',  5,                'string trace level');

($l, $t) = Mail::Reporter->defaultTrace('PROGRESS');
is($l, 'PROGRESS',                  'string log level');
cmp_ok($l, '==',  3,                'numeric log level');

is($t, 'PROGRESS',                  'string trace level');
cmp_ok($t, '==',  3,                'string trace level');

($l, $t) = Mail::Reporter->defaultTrace('WARNING', 'WARNINGS');
is($l, 'WARNING',                   'string log level');
cmp_ok($l, '==',  4,                'numeric log level');

is($t, 'WARNING',                   'string trace level');
cmp_ok($t, '==',  4,                'string trace level');

#
# Reporting levels
#

my $rep = Mail::Reporter->new;

ok(defined $rep);
is($rep->log, 'WARNING',            'Default log-level');
cmp_ok($rep->log, '==', 4);
$l = $rep->log;
is($l, 'WARNING',                   'Default log-level');
cmp_ok($l, '==', 4);

is($rep->trace, 'WARNING',          'Default trace-level');
cmp_ok($rep->trace, '==', 4);
$t = $rep->trace;
is($t, 'WARNING',                   'Default trace-level');
cmp_ok($t, '==', 4);

cmp_ok($rep->trace('ERROR'), '==', 5,   'Check error level numbers');

my $catch;
{  local $SIG{__WARN__} = sub { $catch = shift };
   $rep->log(ERROR => 'a test');   # \n will be added
}
is($catch, "ERROR: a test\n",           'Stored one error text');
cmp_ok($rep->report('ERRORS'), '==', 1, 'Counts one error');
is(($rep->report('ERRORS'))[0], "a test\n", 'Correctly stored text');

undef $catch;
{  local $SIG{__WARN__} = sub { $catch = shift };
   $rep->log(WARNING => "filter\n");
}
ok(!defined $catch,                       'No visible warnings');
cmp_ok($rep->report('WARNING'), '==', 1,  'Count logged warnings');
cmp_ok($rep->report('ERROR'), '==', 1,    'Count logged errors');
cmp_ok($rep->report, '==', 2,             'Count all logged messages');
is(($rep->report('WARNINGS'))[0], "filter\n", 'Just one \n');

my @reps = $rep->report;
is($reps[0][0], 'WARNING',                'Checking report()');
is($reps[0][1], "filter\n");
is($reps[1][0], 'ERROR');
is($reps[1][1], "a test\n");

@reps = $rep->reportAll;
is($reps[0][0], $rep,                     'Checking reportAll()');
is($reps[0][1], 'WARNING');
is($reps[0][2], "filter\n");
is($reps[1][0], $rep);
is($reps[1][1], 'ERROR');
is($reps[1][2], "a test\n");

cmp_ok($rep->errors, '==', 1,             'Check errors() short-cut');
cmp_ok($rep->warnings, '==', 1,           'Check warnings() short-cut');

#
# Check merging reports
#

my $r2 = Mail::Reporter->new(trace => 'NONE', log => 'DEBUG');
ok(defined $r2,                           'Another traceable object');
isa_ok($r2, 'Mail::Reporter');
ok($r2->log(WARNING => 'I warn you!'));
ok($r2->log(ERROR => 'You are in error'));
ok($r2->log(ERROR => 'I am sure!!'));
ok($r2->log(NOTICE => 'Don\'t notice me'));
$rep->addReport($r2);

@reps = $rep->reportAll;
cmp_ok(@{$reps[0]}, '==', 3);
is($reps[0][0], $rep,                     'Checking reportAll()');
is($reps[0][1], 'NOTICE');
is($reps[0][2], "Don't notice me\n");
cmp_ok(@{$reps[1]}, '==', 3);
is($reps[1][0], $rep);
is($reps[1][1], 'WARNING');
is($reps[1][2], "filter\n");
cmp_ok(@{$reps[2]}, '==', 3);
is($reps[2][0], $rep);
is($reps[2][1], 'WARNING');
is($reps[2][2], "I warn you!\n");
cmp_ok(@{$reps[3]}, '==', 3);
is($reps[3][0], $rep);
is($reps[3][1], 'ERROR');
is($reps[3][2], "a test\n");
cmp_ok(@{$reps[4]}, '==', 3);
is($reps[4][0], $rep);
is($reps[4][1], 'ERROR');
is($reps[4][2], "You are in error\n");
cmp_ok(@{$reps[5]}, '==', 3);
is($reps[5][0], $rep);
is($reps[5][1], 'ERROR');
is($reps[5][2], "I am sure!!\n");

