#!/usr/bin/perl

#
# Test appending messages on Mbox folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t);
use Mail::Box::Manager;
use Mail::Message::Construct;
use Tools;

use File::Compare;
use File::Copy;

BEGIN {plan tests => 29}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $empty = File::Spec->catfile('t', 'empty');

copy $src, $cpy
    or die "Cannot create test folder $cpy: $!\n";
unlink $empty;

my $mgr = Mail::Box::Manager->new;

my @fopts =
  ( lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
  );

my $folder = $mgr->open
  ( folder    => "=$cpyfn"
  , folderdir => 't'
  , @fopts
  );

die "Couldn't read $cpy: $!\n"
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

my @appended = $mgr->appendMessage("=$cpyfn", $msg);
ok($folder->messages==46);
ok(@appended==1);
ok($appended[0]->isa('Mail::Box::Message'));

ok($mgr->openFolders==1);
$mgr->close($folder);
ok($mgr->openFolders==0);

my $msg2 = Mail::Message->build
  ( From      => 'me_too@example.com'
  , To        => 'yourself@anywhere.aq'
  , Subject   => 'Just one more try'
  , data      => [ "a short message\n", "of two lines.\n" ]
  );

my $old_size = -s $cpy;

@appended = $mgr->appendMessage($cpy, $msg2
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  , access    => 'rw'
  );
ok(@appended==1);

ok($mgr->openFolders==0);
ok($old_size != -s $cpy);

$folder = $mgr->open
  ( folder    => "=$cpyfn"
  , folderdir => 't'
  , @fopts
  , access    => 'rw'
  );

my $sec = $mgr->open
  ( folder    => '=empty'
  , folderdir => 't'
  , @fopts
  , create    => 1
  );

ok($folder);
ok($folder->messages==47);
ok($sec);
ok($sec->messages==0);
ok($mgr->openFolders==2);

my $move = $folder->message(1);
ok(defined $move);

my @moved = $mgr->moveMessage($sec, $move);
ok(@moved==1);
ok($moved[0]->isa('Mail::Box::Message'));
ok($moved[0]->folder->name eq $sec->name);

ok($move->deleted);
ok($folder->messages==47);
ok($sec->messages==1);

my $copy   = $folder->message(2);
my @copied = $mgr->copyMessage($sec, $copy);
ok(@copied==1);
ok($copied[0]->isa('Mail::Box::Message'));
ok(!$copy->deleted);
ok($folder->messages==47);
ok($sec->messages==2);

$folder->close;
$sec->close;
ok(-f $empty);
ok(-s $empty);

unlink $empty;
