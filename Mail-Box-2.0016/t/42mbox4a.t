#!/usr/bin/perl -w

#
# Test appending messages on Mbox folders.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Manager;
use Mail::Message::Construct;
use Tools;

use Test;
use File::Compare;
use File::Copy;
use File::Spec;

BEGIN {plan tests => 21}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig  = File::Spec->catfile('t', 'mbox.src');
my $src   = File::Spec->catfile('t', 'mbox.cpy');
my $empty = File::Spec->catfile('t', 'empty');

copy $orig, $src
    or die "Cannot create test folder $src: $!\n";
unlink $empty;

my $mgr = Mail::Box::Manager->new;

my @fopts =
  ( lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
  );

my $folder = $mgr->open
  ( folder    => '=mbox.cpy'
  , folderdir => 't'
  , @fopts
  );

die "Couldn't read $src: $!\n"
    unless $folder;

ok($folder->messages==45);

# Add a message which is already in the opened folder.  This should
# be ignored.

$folder->addMessage($folder->message(3)->clone);
ok($folder->messages==45);

#
# Create an Mail::Message and add this to the open folder.
#

my $msg = Mail::Message->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , data    => [ "a short message\n", "of two lines.\n" ]
  );

$mgr->appendMessage('=mbox.cpy', $msg);
ok($folder->messages==46);

ok($mgr->openFolders==1);
$mgr->close($folder);
ok($mgr->openFolders==0);

my $msg2 = Mail::Message->build
  ( From      => 'me_too@example.com'
  , To        => 'yourself@anywhere.aq'
  , Subject   => 'Just one more try'
  , data      => [ "a short message\n", "of two lines.\n" ]
  );

my $old_size = -s $src;

$mgr->appendMessage($src, $msg2
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  , access    => 'rw'
  );

ok($mgr->openFolders==0);
ok($old_size != -s $src);

$folder = $mgr->open
  ( folder    => '=mbox.cpy'
  , folderdir => 't'
  , @fopts
  , access    => 'rw'
  );

my $sec = $mgr->open
  ( folder    => '=empty'
  , folderdir => 't'
  , @fopts
  , create => 1
  );

ok($folder);
ok($folder->messages==47);
ok($sec);
ok($sec->messages==0);
ok($mgr->openFolders==2);

my $move = $folder->message(1);
ok(defined $move);
$mgr->moveMessage($sec, $move);

ok($move->deleted);
ok($folder->messages==47);
ok($sec->messages==1);

my $copy = $folder->message(2);
$mgr->copyMessage($sec, $copy);
ok(!$copy->deleted);
ok($folder->messages==47);
ok($sec->messages==2);

$folder->close;
$sec->close;
ok(-f $empty);
ok(-s $empty);

unlink $empty;
