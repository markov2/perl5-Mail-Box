#!/usr/local/bin/perl -w

#
# Test the folder manager
#

use Test;
use lib '..';
use strict;

BEGIN {plan tests => 10}

use Mail::Box::Manager;

my $src  = 't/mbox.src';
my $new  = 't/create';

my $manager = Mail::Box::Manager->new;

my $folder  = $manager->open
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  );

ok(defined $folder);
ok($folder->isa('Mail::Box::Mbox'));

$SIG{__WARN__} = sub {}; # ignore warning.
my $second = $manager->open
  ( folder       => $src
  , lock_method  => 'NONE'
  );
delete $SIG{__WARN__};

ok(!defined $second);
ok($manager->openFolders==1);

# Test a creation.
ok(! -f $new);
my $n = $manager->open
  ( folder       => $new
  , type         => 'mbox'
  , lock_method  => 'NONE'
  );
ok(! -f $new);
ok(! $n);

$n = $manager->open
  ( folder       => $new
  , lock_method  => 'NONE'
  , type         => 'mbox'
  , create       => 1
  );
ok(-f $new);
ok($n);
ok(-z $new);

unlink $new;
exit 0;
