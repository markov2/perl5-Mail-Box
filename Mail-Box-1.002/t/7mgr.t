#!/usr/local/bin/perl -w

#
# Test the folder manager
#

use strict;

use Test;
use File::Spec;

BEGIN {plan tests => 10}

use lib '..';
use Mail::Box::Manager;

my $src  = File::Spec->catfile('t', 'mbox.src');
my $new  = File::Spec->catfile('t', 'create');

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
