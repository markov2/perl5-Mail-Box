#!/usr/bin/perl

#
# Test appending messages on Maildir folders.
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

BEGIN {
   if($^O =~ /mswin/i)
   {   warn "Maildir filenames are incompatible with Windows";
       plan tests => 0;
       exit 0;
   }

   plan tests => 14;
}

my $mdsrc = File::Spec->catfile('t', 'maildir.src');
unpack_mbox2maildir($src, $mdsrc);

my $mgr = Mail::Box::Manager->new;
my $folder = $mgr->open
  ( folder       => $mdsrc
  , folderdir    => 't'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
  );

die "Couldn't read $mdsrc: $!\n"
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
ok(defined $added);
ok(ref $added eq 'Mail::Message');

ok(!$message3->isDelayed);

my $coerced = $folder->addMessage($added);    # coerced == added (reblessed)
ok(ref $added eq 'Mail::Box::Maildir::Message');
ok(ref $coerced eq 'Mail::Box::Maildir::Message');

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

$coerced = $mgr->appendMessage($mdsrc, $msg);
ok($coerced->isa('Mail::Box::Maildir::Message'));
ok($folder->messages==46);

ok($mgr->openFolders==1);
$mgr->close($folder);      # changes are not saved.
ok($mgr->openFolders==0);

$mgr->appendMessage($mdsrc, $msg
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  , access    => 'rw'
  );

clean_dir $mdsrc;
