#!/usr/bin/perl -T

#
# Test the locking methods.
#

use strict;
use warnings;

use Tools;
use Mail::Box::Locker::Flock;

use File::Spec;
use Test::More;

BEGIN
{   if($windows)
    {   plan skip_all => "not available on MicroSoft Windows";
        exit 0;
    }

    plan tests => 7;
}

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

my $lockfile  = File::Spec->catfile('folders', 'lockfiletest');
unlink $lockfile;
open OUT, '>', $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'FLOCK'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker,                                       'create locker');
is($locker->name, 'FLOCK',                        'lock name');

ok($locker->lock,                                 'do lock');
ok(-f $lockfile,                                  'locked file exists');
ok($locker->hasLock,                              'lock received');

# Already got lock, so should return immediately.
ok($locker->lock,                                 'relock no problem');

$locker->unlock;
ok(! $locker->hasLock,                            'unlocked');

close OUT;
unlink $lockfile;
