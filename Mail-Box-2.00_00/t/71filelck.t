#!/usr/bin/perl -w

#
# Test the locking methods.
#

use strict;
use lib '/home/markov/fake';
use Mail::Box::Mbox;

use Test;
use File::Compare;
use File::Spec;

BEGIN {plan tests => 4}

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
