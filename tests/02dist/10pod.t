#!/usr/bin/perl
use warnings;
use strict;

use Test::More;
use Test::Pod;
use File::Spec::Functions qw/updir catdir/;

my @dirs = map { catdir updir, $_ }
       qw/blib script/;

all_pod_files_ok all_pod_files @dirs;
