#!/usr/local/bin/perl -w

#
# Test the locking methods.
#

use Test;
use File::Compare;
use strict;
use lib '..';

BEGIN {plan tests => 4}

use Mail::Box::Mbox;

my $src  = 't/mbox.src';
unlink "$src.lock";

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'dotlock'
  , lazy_extract => 'ALWAYS'
  );

ok(defined $folder);
ok($folder->hasLock);

# Already got lock, so should return immediately.
ok($folder->lock);

$folder->unlock;
ok(not $folder->hasLock);
