#!/usr/local/bin/perl -w

#
# Test writing of MH folders.
#

use Test;
use File::Compare;
use File::Copy;
use lib '..', 't';
use strict;

use Mail::Box::MH;
use Mail::Box::Mbox;

use Tools;

BEGIN {plan tests => 2}

my $orig = 't/mbox.src';
my $src = 't/mh.src';

unpack_mbox($orig, $src);

my $folder = new Mail::Box::MH
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  , keep_index   => 1
  );

ok(defined $folder);

my $msg3 = $folder->message(3);
ok(not $msg3->isParsed);

# Nothing yet...

$folder->close;

clean_dir $src;
