#!/usr/bin/perl

#
# Test writing of maildir folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Maildir;
use Tools;

use File::Compare;
use File::Copy;

# under development
BEGIN {plan tests => 0};
__END__

BEGIN {plan tests => 31}

my $mdsrc = File::Spec->catfile('t', 'maildir.src');

unpack_mbox2maildir($src, $mdsrc);

my $folder = new Mail::Box::Maildir
  ( folder       => $mdsrc
  , folderdir    => 't'
  , extract      => 'LAZY'
  , access       => 'rw'
  );

ok(defined $folder);

#
# Count files flagged for deletion  (T flag)
#

my $to_be_deleted =0;
$_->deleted && $to_be_deleted++  foreach $folder->messages;
ok($to_be_deleted==7);

$folder->close;

#
# Reopen the folder and see whether the messages flagged for deletion
# are away.
#

$folder = new Mail::Box::Maildir
  ( folder       => $mdsrc
  , folderdir    => 't'
  , extract      => 'LAZY'
  , access       => 'rw'
  );

ok($folder->messages==38);

my $msg6 = $folder->message(6);
ok($msg6->filename =~ m/:2,$/);
ok(!$msg6->label('draft'));
ok(!$msg6->label('flagged'));
ok(!$msg6->label('replied'));
ok(!$msg6->label('seen'));
ok(!$msg6->modified);

my $msg12 = $folder->message(12);
ok($msg12->filename =~ m/:2,DFRS$/);
ok($msg12->label('draft'));
ok($msg12->label('flagged'));
ok($msg12->label('replied'));
ok($msg12->label('seen'));

ok(!$msg12->label(flagged => 0));
ok(!$msg12->label('flagged'));
ok($msg12->filename =~ m/:2,DRS$/);

ok(!$msg12->label(draft => 0));
ok(!$msg12->label('draft'));
ok($msg12->filename =~ m/:2,RS$/);

ok(!$msg12->label(seen => 0));
ok(!$msg12->label('seen'));
ok($msg12->filename =~ m/:2,R$/);

ok($msg12->label(flagged => 1));
ok($msg12->label('flagged'));
ok($msg12->filename =~ m/:2,FR$/);

ok(!$msg12->label(flagged => 0, replied => 0));
ok(!$msg12->label('flagged'));
ok(!$msg12->label('replied'));
ok($msg12->filename =~ m/:2,$/);

ok(!$msg12->modified);
clean_dir $mdsrc;
