#!/usr/bin/perl -w
#
# Test the processing of a message header, in this case purely the reading
# from a file.
#

use Test;
use strict;

use lib '/home/markov/fake';
use Mail::Message::Head;
use Mail::Box::Parser;

BEGIN {plan tests => 20}

use File::Spec;
my $inbox = File::Spec->catfile('t', 'mbox.src');

my $h = Mail::Message::Head->new;
ok(defined $h);

my $parser = Mail::Box::Parser->openFile(filename => $inbox);
ok($parser);

