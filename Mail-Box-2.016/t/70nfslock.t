#!/usr/bin/perl

#
# Test the locking methods.
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Box::Locker::NFS;

use File::Spec;

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

BEGIN {plan tests => 7}

my $lockfile  = File::Spec->catfile('t', 'lockfiletest');
unlink $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'nfs'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker);
ok($locker->name eq 'NFS');

ok($locker->lock);
ok(-f $lockfile);
ok($locker->hasLock);

# Already got lock, so should return immediately.
ok($locker->lock);

$locker->unlock;
ok(not $locker->hasLock);
