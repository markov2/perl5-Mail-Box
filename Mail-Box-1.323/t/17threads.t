#!/usr/local/bin/perl -w
#
# Test threads over multi-folders.
#

use Test;
use strict;
use lib '/home/markov/MailBox1/fake';
use File::Spec;

BEGIN {plan tests => 1}

#use Mail::Box::Manager;

my $src  = File::Spec->catfile('t', 'mbox.src');
my $dest = File::Spec->catfile('t', 'mbox.cpy');

warn "   * Multi-folder threads status ALPHA\n";
ok(1);
