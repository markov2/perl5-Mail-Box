#!/usr/bin/perl -w

#
# Test mh-sequences
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Manager;
use Tools;

use Test;
use File::Spec;

BEGIN {plan tests => 10}

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mh.src');
my $seq  = File::Spec->catfile($src, '.mh_sequences');

#
# Unpack the file-folder.
#

clean_dir $src;
unpack_mbox($orig, $src);

# Create a sequences file.
open SEQ, ">$seq" or die "Cannot write to $seq: $!\n";

# Be warned that message number 13 has been skipped from the MH-box.
print SEQ <<'MH_SEQUENCES';
unseen: 12-15 3 34 36 16
cur: 1
MH_SEQUENCES

close SEQ;

my $mgr = Mail::Box::Manager->new;

my $folder = $mgr->open
  ( folder       => $src
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
  );

die "Couldn't read $src: $!\n" unless $folder;

ok($folder->message(1)->label('seen'));
ok(not $folder->message(2)->label('seen'));
ok($folder->message(3)->label('seen'));

ok($folder->message(0)->label('current'));
ok($folder->current->messageID eq $folder->message(0)->messageID);

ok(not $folder->message(1)->label('current'));
$folder->current($folder->message(1));
ok(not $folder->message(0)->label('current'));
ok($folder->message(1)->label('current'));

$folder->write;

open SEQ, $seq or die "Cannot read from $seq: $!\n";
my @seq = <SEQ>;
close SEQ;

my ($cur)    = grep /^cur\: /, @seq;
ok($cur, "cur: 2\n");
my ($unseen) = grep /^unseen\: /, @seq;
ok($unseen, "unseen: 3 12-15 33 35\n");

clean_dir $src;
