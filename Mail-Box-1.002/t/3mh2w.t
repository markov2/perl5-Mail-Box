#!/usr/local/bin/perl -w

#
# Test writing of MH folders.
#

use strict;
use Test;
use File::Compare;
use File::Copy;
use File::Spec;

use lib '..', 't';
use Mail::Box::MH;
use Mail::Box::Mbox;

use Tools;

BEGIN {plan tests => 13}

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mh.src');

clean_dir $src;
unpack_mbox($orig, $src);

my $folder = new Mail::Box::MH
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  , keep_index   => 1
  );

ok(defined $folder);
ok($folder->messages==45);

my $msg3 = $folder->message(3);

# Nothing yet...

$folder->write
  ( renumber     => 0
  );

ok(cmplists [sort {$a cmp $b} listdir $src],
            [sort {$a cmp $b} '.index', '.mh_sequences', 1..12, 14..46]
  );

$folder->write
  ( renumber     => 1
  );

ok(cmplists [sort {$a cmp $b} listdir $src],
            [sort {$a cmp $b} '.index', '.mh_sequences', 1..45]
  );

$folder->message(2)->delete;
$folder->write;
ok(cmplists [sort {$a cmp $b} listdir $src],
            [sort {$a cmp $b} '.index', '.mh_sequences', 1..44]
  );
ok($folder->allMessages==44);
ok($folder->messages==44);

$folder->message(8)->delete;
ok($folder->allMessages==44);
ok($folder->messages==43);

$folder->write
  ( keep_deleted => 1
  );
ok($folder->allMessages==44);
ok($folder->messages==43);

$folder->write;
ok($folder->allMessages==43);
ok($folder->messages==43);
$folder->close;

clean_dir $src;
