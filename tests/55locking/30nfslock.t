#!/usr/bin/perl

#
# Test the locking methods.
#

use strict;
use warnings;

use Tools;
use Test::More;
use Mail::Box::Locker::NFS;

use File::Spec;

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

BEGIN {
   if($windows)
   {   plan skip_all => "not available on MicroSoft Windows.";
       exit 0;
   }

   plan tests => 7;
}

my $lockfile  = File::Spec->catfile('folders', 'lockfiletest');
unlink $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'nfs'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker);
is($locker->name, 'NFS');

ok($locker->lock);
ok(-f $lockfile);
ok($locker->hasLock);

# Already got lock, so should return immediately.
ok($locker->lock);

$locker->unlock;
ok(not $locker->hasLock);
