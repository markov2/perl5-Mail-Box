#!/usr/bin/perl -w
#
# Test threads over multi-folders.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);

use File::Spec;
use Test;

BEGIN {plan tests => 1}

#use Mail::Box::Manager;
use Tools;

my $src  = File::Spec->catfile('t', 'mbox.src');
my $dest = File::Spec->catfile('t', 'mbox.cpy');

warn "   * Multi-folder threads status ALPHA (not tested)\n";
ok(1);
