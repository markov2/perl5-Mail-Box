#!/usr/bin/env perl
use warnings;
use strict;

use Test::More;
use Test::Pod;
use File::Spec::Functions qw/updir catdir/;

BEGIN
{   eval "use Test::Pod 1.00";

    plan skip_all => "Test::Pod 1.00 required for testing POD"
        if $@;

    plan skip_all => "devel home uses OODoc"
        if qx(/bin/pwd) =~ m[^/home/markov/];
}

my @dirs = map { catdir updir, $_ } qw(lib script);
all_pod_files_ok all_pod_files @dirs;

