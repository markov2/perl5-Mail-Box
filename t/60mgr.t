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

warn "   * Various packages\n";

BEGIN {plan tests => 16}

my $new  = File::Spec->catfile('t', 'create');
unlink $new;

my $manager = Mail::Box::Manager->new
 ( log      => 'NOTICES'
 , trace    => 'ERRORS'
 );

my $folder  = $manager->open
  ( folder    => $src
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  );

ok(defined $folder);
isa_ok($folder, 'Mail::Box::Mbox');

my $second = $manager->open
 ( folder       => $src
 , lock_type    => 'NONE'
 );

ok(defined $second);
is($second, $folder);
my @notices = $manager->report('NOTICES');
cmp_ok(@notices, "==", 1);

$notices[-1] =~ s#\\#/#g;  # Windows
is($notices[-1], "Folder t/mbox.src is already open.\n");
cmp_ok($manager->openFolders, "==", 1);

undef $second;
cmp_ok($manager->openFolders, "==", 1);

my $n = $manager->open
 ( folder       => $new
 , folderdir    => 't'
 , type         => 'mbox'
 , lock_type    => 'NONE'
 );
ok(! -f $new);
ok(not defined $n);
@notices = $manager->report('NOTICES');
cmp_ok(@notices, "==", 1);

my @warnings = $manager->report('WARNINGS');
cmp_ok(@warnings, "==", 1);
$warnings[-1] =~ s#\\#/#g;  # Windows
is($warnings[-1], "Folder t/create does not exist (mbox).\n");

$manager->log('WARNINGS');  # back to default reporting.
$manager->trace('WARNINGS');

my $p = $manager->open
  ( folder       => $new
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , type         => 'mbox'
  , create       => 1
  , access       => 'w'
  );

ok(defined $p);
ok(-f $new);
ok(-z $new);

unlink $new;
exit 0;
