#!/usr/local/bin/perl -w

#
# Test appending messages on Mbox folders.
#

use strict;
use Test;
use File::Compare;
use File::Copy;
use File::Spec;

use lib '..';
use Mail::Box::Manager;

BEGIN {plan tests => 18}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mbox.cpy');
my $empty= File::Spec->catfile('t', 'empty');

copy $orig, $src
    or die "Cannot create test folder $src: $!\n";

my $mgr = Mail::Box::Manager->new;

my @fopts =
  ( lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  , save_on_exit => 0
  );

my $folder = $mgr->open(folder => $src, @fopts);

die "Couldn't read $src: $!\n"
    unless $folder;

ok($folder->messages==45);

# Add a message which is already in the opened folder.  This should
# be ignored.

$folder->addMessage($folder->message(3));
ok($folder->messages==45);

#
# Create an MIME::Entity and add this to the open folder.
#

my $msg = MIME::Entity->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , Data    => [ "a short message\n", "of two lines.\n" ]
  );

$mgr->appendMessage($src, $msg);
ok($folder->messages==46);

ok($mgr->openFolders==1);
$mgr->close($folder);
ok($mgr->openFolders==0);

my $msg2 = MIME::Entity->build
  ( From    => 'me_too@example.com'
  , To      => 'yourself@anywhere.aq'
  , Subject => 'Just one more try'
  , Data    => [ "a short message\n", "of two lines.\n" ]
  );

my $old_size = -s $src;

$mgr->appendMessage($src, $msg2
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  );

ok($mgr->openFolders==0);
ok($old_size != -s $src);

$folder = $mgr->open(folder => $src, @fopts, access => 'rw');
my $sec = $mgr->open(folder => $empty, @fopts, create => 1);

ok($folder);
ok($folder->messages==46);
ok($sec);
ok($sec->messages==0);
ok($mgr->openFolders==2);
$mgr->moveMessage($sec, $folder->message(1));
ok($folder->messages==45);
ok($folder->allMessages==46);
ok($sec->messages==1);
$mgr->copyMessage($sec, $folder->message(2));
ok($folder->messages==45);
ok($sec->messages==2);

$folder->close;
$sec->close;
ok(-s $sec);

unlink($empty);
