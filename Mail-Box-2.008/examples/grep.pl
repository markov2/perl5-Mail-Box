#!/usr/bin/perl

# Demonstration of a simple search.
#
# This code can be used and modified without restriction.
# Mark Overmeer, <mailbox@overmeer.net>, 17 feb 2002

use warnings;
use strict;
use lib '..', '.';

use Mail::Box::Manager 2.008;
use Mail::Box::Search::Grep;

#
# Get the command line arguments.
#

die "Usage: $0 mailbox pattern\n"
    unless @ARGV==2;

my ($mailbox, $pattern) = @ARGV;

my $mgr = Mail::Box::Manager->new;
my $folder = $mgr->open($mailbox)
   or die "Cannot open folder $mailbox.\n";

my $grep = Mail::Box::Search::Grep->new
  ( in      => 'MESSAGE'
  , match   => qr/$pattern/
  , details => 'PRINT'
  );

$grep->search($folder);

$folder->close;
