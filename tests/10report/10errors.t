#!/usr/bin/perl
#
# Test reporting warnings, errors and family.
#

use Test::More;

use strict;
use warnings;

use lib qw(. t);
use Mail::Reporter;
use Tools;

BEGIN {plan tests => 24}

my $rep = Mail::Reporter->new;

ok(defined $rep);
is($rep->log,   'WARNING',              'Default log-level');
is($rep->trace, 'WARNING',              'Default trace-level');
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
