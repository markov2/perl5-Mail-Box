#!/usr/bin/perl

#
# Test folder-to-folder copy
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);
use Tools;
use Mail::Box::Manager;
use File::Copy;

use IO::Scalar;

BEGIN {plan tests => 26}

copy $src, $cpy or die "Copy failed";

#
# Build a complex system with MH folders and sub-folders.
#

my $mgr    = Mail::Box::Manager->new;

my $folder = $mgr->open($cpy);
ok(defined $folder);

unlink qw/a b c d e/;

my $A = $mgr->open('a', type => 'mh', create => 1, access => 'w');
ok(defined $A);

$mgr->copyMessage($A, $folder->message($_)) for 0..9;

my $b = $A->openSubFolder('b', create => 1, access => 'w');
ok(defined $b);
$mgr->copyMessage($b, $folder->message($_)) for 10..19;
cmp_ok($b->messages, "==", 10);
$b->close;

my $c = $A->openSubFolder('c', create => 1, access => 'w');
ok(defined $c);
$mgr->copyMessage($c, $folder->message($_)) for 20..29;

my $d = $c->openSubFolder('d', create => 1, access => 'w');
ok(defined $c);
$mgr->copyMessage($d, $folder->message($_)) for 30..39;

$d->close;
$c->close;
$A->close;

$folder->close;
cmp_ok($mgr->openFolders , "==",  0);

#
# Convert the built MH structure into MBOX
#

$A = $mgr->open('a', access => 'rw');
ok($A);

my @sub = sort $A->listSubFolders;
cmp_ok(@sub, "==", 2);
is($sub[0], 'b');
is($sub[1], 'c');

my $e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
cmp_ok($A->messages, "==", 10);

$A->message($_)->delete for 3,4,8;
ok(defined $A->copyTo($e, select => 'ALL', subfolders => 0));
cmp_ok($e->messages, "==", 10);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $A->copyTo($e, select => 'DELETED', subfolders => 0));
cmp_ok($e->messages, "==", 3);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $A->copyTo($e, select => 'ACTIVE', subfolders => 'FLATTEN'));
cmp_ok($e->messages, "==", 37);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $A->copyTo($e, select => 'ACTIVE', subfolders => 'RECURSE'));
cmp_ok($e->messages, "==", 7);

my @subs = sort $e->listSubFolders;
cmp_ok(@subs, "==", 2);
is($subs[0], 'b');
is($subs[1], 'c');

$b = $e->openSubFolder('b');
ok(defined $b);
isa_ok($b, 'Mail::Box::Mbox');
cmp_ok($b->messages , "==",  10);

$b->close;

$e->delete;

