#!/usr/bin/perl

#
# Test the folder manager
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);
use Tools;
use Mail::Box::Manager;

use File::Spec;

BEGIN {plan tests => 16}

my $new  = File::Spec->catfile('folders', 'create');
unlink $new;

my $manager = Mail::Box::Manager->new
 ( log      => 'NOTICES'
 , trace    => 'ERRORS'
 );

my $folder  = $manager->open
  ( folder    => $src
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  );

ok(defined $folder,                              'open folder');
isa_ok($folder, 'Mail::Box::Mbox');

my $second = $manager->open
 ( folder       => $src
 , lock_type    => 'NONE'
 );

ok(defined $second,                              'open same folder');
is($second, $folder,                             'same: no new folder');
my @notices = $manager->report('NOTICES');
cmp_ok(@notices, "==", 1,                        'mgr noticed double');

$notices[-1] =~ s#\\#/#g;  # Windows
is($notices[-1], "Folder folders/mbox.src is already open.\n");
cmp_ok($manager->openFolders, "==", 1,           'only one folder open');

undef $second;
cmp_ok($manager->openFolders, "==", 1,           'second closed, still one open');

my $n = $manager->open
 ( folder       => $new
 , folderdir    => 't'
 , type         => 'mbox'
 , lock_type    => 'NONE'
 );
ok(! -f $new,                                    'folder file does not exist');
ok(! defined $n,                                 'open non-ex does not succeed');
@notices = $manager->report('NOTICES');
cmp_ok(@notices, "==", 1,                        'no new notices since "double"');

my @warnings = $manager->report('WARNINGS');
cmp_ok(@warnings, "==", 1,                       'new warning');
$warnings[-1] =~ s#\\#/#g;  # Windows
is($warnings[-1], "Folder folders/create does not exist (mbox).\n");

$manager->log('WARNINGS');  # back to default reporting.
$manager->trace('WARNINGS');

my $p = $manager->open
  ( folder       => $new
  , lock_type    => 'NONE'
  , type         => 'mbox'
  , create       => 1
  , access       => 'w'
  );

ok(defined $p,                                   'open non-existing with create');
ok(-f $new,                                      'new folder created');
ok(-z $new,                                      'new folder is empty');

unlink $new;
exit 0;
