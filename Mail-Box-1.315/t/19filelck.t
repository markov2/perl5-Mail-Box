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
use File::Spec;

my $src  = File::Spec->catfile('t', 'mbox.src');
unlink "$src.lock";

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'FILE'
  , lazy_extract => 'ALWAYS'
  );

ok(defined $folder);
ok($folder && $folder->hasLock);

# Already got lock, so should return immediately.
ok($folder && $folder->lock);

$folder->unlock if $folder;
ok($folder && not $folder->hasLock);
