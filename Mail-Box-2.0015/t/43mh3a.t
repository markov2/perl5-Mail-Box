#!/usr/bin/perl -w

#
# Test appending messages on MH folders.
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

BEGIN {plan tests => 10}

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mh.src');

#
# Unpack the file-folder.
#

clean_dir $src;
unpack_mbox($orig, $src);

my $mgr = Mail::Box::Manager->new;

my $folder = $mgr->open
  ( folder       => $src
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
  );

die "Couldn't read $src: $!\n"
    unless $folder;

# We checked this in other scripts before, but just want to be
# sure we have enough messages again.

ok($folder->messages==45);

# Add a message which is already in the opened folder.  However, the
# message heads are not yet parsed, hence the message can not be
# ignored.

my $message3 = $folder->message(3);
ok($message3->isDelayed);
my $added = $message3->clone;
ok(!$message3->isDelayed);

$folder->addMessage($added);
ok($folder->messages==45);

ok(not $message3->deleted);
ok($added->deleted);

#
# Create an Mail::Message and add this to the open folder.
#

my $msg = Mail::Message->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , data    => [ "a short message\n", "of two lines.\n" ]
  );

$mgr->appendMessage($src, $msg);
ok($folder->messages==46);

ok($mgr->openFolders==1);
$mgr->close($folder);      # changes are not saved.
ok($mgr->openFolders==0);

$mgr->appendMessage($src, $msg
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  , access    => 'rw'
  );

ok(-f File::Spec->catfile($src, "47"));  # skipped 13, so new is 46+1

clean_dir $src;
