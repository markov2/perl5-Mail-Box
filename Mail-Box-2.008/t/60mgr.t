#!/usr/bin/perl

#
# Test the folder manager
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
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
ok($folder->isa('Mail::Box::Mbox'));

my $second = $manager->open
 ( folder       => $src
 , lock_type    => 'NONE'
 );

ok(defined $second);
ok($second eq $folder);
my @notices = $manager->report('NOTICES');
ok(@notices==1);
ok($notices[-1] eq "Folder t/mbox.src is already open.\n");
ok($manager->openFolders==1);

undef $second;
ok($manager->openFolders==1);

my $n = $manager->open
 ( folder       => $new
 , folderdir    => 't'
 , type         => 'mbox'
 , lock_type    => 'NONE'
 );
ok(! -f $new);
ok(not defined $n);
@notices = $manager->report('NOTICES');
ok(@notices==1);

my @warnings = $manager->report('WARNINGS');
ok(@warnings==1);
ok($warnings[-1] eq "Folder t/create does not exist.\n");

my $p = $manager->open
  ( folder       => $new
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , type         => 'mbox'
  , create       => 1
  );

ok(-f $new);
ok(defined $p);
ok(-z $new);

unlink $new;
exit 0;
