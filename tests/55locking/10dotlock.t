#!/usr/bin/env perl
#
# Test the locking methods.
#

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More tests => 7;
use File::Spec;

use Mail::Box::Locker::DotLock;

my $fakefolder = bless {MB_foldername=> 'this'}, 'Mail::Box';

my $base      = -d 'folders' ? 'folders'
              : File::Spec->catfile('tests', 'folders');

my $lockfile  = File::Spec->catfile($base, 'lockfiletest');

unlink $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'DotLock'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
 , folder  => $fakefolder
 );

ok($locker);
is($locker->name, 'DOTLOCK', 'locker name');

ok($locker->lock,    'can lock');
ok(-f $lockfile,     'lockfile found');
ok($locker->hasLock, 'locked status');

# Already got lock, so should return immediately.
my $warn = '';
{  $SIG{__WARN__} = sub {$warn = "@_"};
   $locker->lock;
}
ok($warn =~ m/already locked/, 'second attempt');

$locker->unlock;
ok(! $locker->hasLock, 'released lock');
