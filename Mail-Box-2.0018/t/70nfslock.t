#!/usr/bin/perl -w

#
# Test the locking methods.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Locker::NFS;
use Tools;

use Test;
use File::Spec;

BEGIN {plan tests => 7}

my $lockfile  = File::Spec->catfile('t', 'lockfiletest');
unlink $lockfile;

my $locker = Mail::Box::Locker->new
 ( method  => 'nfs'
 , timeout => 1
 , wait    => 1
 , file    => $lockfile
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
