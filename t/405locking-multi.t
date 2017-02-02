#!/usr/bin/env perl
#
# Test the locking methods.
#

use strict;
use warnings;

use Mail::Box::Test;
use Mail::Box::Locker::Multi;

use Test::More tests => 7;
use File::Spec;

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

my $lockfile  = File::Spec->catfile($folderdir, 'lockfiletest');
unlink $lockfile;

if($windows)
{   open my $OUT, '>', $lockfile or die;
    close $OUT;
}

my $locker = Mail::Box::Locker->new
 ( method  => 'MULTI'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker);
is($locker->name, 'MULTI');

ok($locker->lock);
ok(-f $lockfile);
ok($locker->hasLock);

# Already got lock, so should return immediately.
ok($locker->lock);

$locker->unlock;
ok(not $locker->hasLock);
