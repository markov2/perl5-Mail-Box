#!/usr/bin/perl
#
# Test reporting warnings, errors and family.
#

use Test;

use strict;
use warnings;

use lib qw(. t);
use Mail::Reporter;
use Tools;

BEGIN {plan tests => 24}

my $rep = Mail::Reporter->new;

ok($rep);
ok($rep->log   eq 'WARNING');
ok($rep->trace eq 'WARNING');
ok($rep->trace('ERROR') == 5);

my $catch;
{  local $SIG{__WARN__} = sub { $catch = shift };
   $rep->log(ERROR => 'a test');   # \n will be added
}
ok($catch eq "ERROR: a test\n");
ok($rep->report('ERRORS')==1);
ok(($rep->report('ERRORS'))[0] eq "a test\n");

undef $catch;
{  local $SIG{__WARN__} = sub { $catch = shift };
   $rep->log(WARNING => "filter\n");
}
ok(!defined $catch);
ok($rep->report('WARNING')==1);
ok($rep->report('ERROR')==1);
ok($rep->report==2);
ok(($rep->report('WARNINGS'))[0] eq "filter\n");  # no second \n

my @reps = $rep->report;
ok($reps[0][0] eq 'WARNING');
ok($reps[0][1] eq "filter\n");
ok($reps[1][0] eq 'ERROR');
ok($reps[1][1] eq "a test\n");

@reps = $rep->reportAll;
ok($reps[0][0] eq $rep);
ok($reps[0][1] eq 'WARNING');
ok($reps[0][2] eq "filter\n");
ok($reps[1][0] eq $rep);
ok($reps[1][1] eq 'ERROR');
ok($reps[1][2] eq "a test\n");

ok($rep->errors==1);
ok($rep->warnings==1);
