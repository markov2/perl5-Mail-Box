#!/usr/bin/perl

#
# Test folder-to-folder copy
#

use Test;
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

my $a = $mgr->open('a', type => 'mh', create => 1, access => 'w');
ok(defined $a);

$mgr->copyMessage($a, $folder->message($_)) for 0..9;

my $b = $a->openSubFolder('b', create => 1, access => 'w');
ok(defined $b);
$mgr->copyMessage($b, $folder->message($_)) for 10..19;
ok($b->messages==10);
$b->close;

my $c = $a->openSubFolder('c', create => 1, access => 'w');
ok(defined $c);
$mgr->copyMessage($c, $folder->message($_)) for 20..29;

my $d = $c->openSubFolder('d', create => 1, access => 'w');
ok(defined $c);
$mgr->copyMessage($d, $folder->message($_)) for 30..39;

$d->close;
$c->close;
$a->close;

$folder->close;
ok($mgr->openFolders == 0);

#
# Convert the built MH structure into MBOX
#

$a = $mgr->open('a', access => 'rw');
ok($a);

my @sub = sort $a->listSubFolders;
ok(@sub==2);
ok($sub[0] eq 'b');
ok($sub[1] eq 'c');

my $e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok($a->messages==10);

$a->message($_)->delete for 3,4,8;
ok(defined $a->copyTo($e, select => 'ALL', subfolders => 0));
ok($e->messages==10);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $a->copyTo($e, select => 'DELETED', subfolders => 0));
ok($e->messages==3);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $a->copyTo($e, select => 'ACTIVE', subfolders => 'FLATTEN'));
ok($e->messages==37);
$e->delete;

$e = $mgr->open('e', type => 'mbox', create => 1, access => 'rw');
ok(defined $a->copyTo($e, select => 'ACTIVE', subfolders => 'RECURSE'));
ok($e->messages==7);

my @subs = sort $e->listSubFolders;
ok(@subs==2);
ok($subs[0] eq 'b');
ok($subs[1] eq 'c');

$b = $e->openSubFolder('b');
ok(defined $b);
ok($b->isa('Mail::Box::Mbox'));
ok($b->messages == 10);

$b->close;

$e->delete;

