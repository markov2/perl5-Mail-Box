#!/usr/bin/perl
#
# Test processing of header-fields: only single fields, not whole headers.
# This also doesn't cover reading headers from file.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

BEGIN { plan tests => 15 }

use Mail::Message::Field;
use Mail::Box::Parser::Perl;
use Tools;

# Explictly ask for the Perl parser to fold lines.

Mail::Box::Parser->defaultParserType('Mail::Box::Parser::Perl');

warn "   * Parser in pure Perl status: released\n";

#
# Processing of structured lines.
#

my $f = Mail::Message::Field->new('Sender:  B ;  C');
is($f->name, 'sender');
is($f->body, 'B');
like($f->comment , qr/^\s*C\s*/);

# No comment, strip CR LF

my $g = Mail::Message::Field->new("Sender: B\015\012");
is($g->body, 'B');
is($g->comment, "");

# Check toString

my $x = $f->toString;
is($x, "Sender: B ;  C\n");

$x = $g->toString;
is($x, "Sender: B\n");

# Now check folding.

my $k = Mail::Message::Field->new(Sender => 'short line');
is($k->toString, "Sender: short line\n");
my @klines = $k->toString;
cmp_ok(@klines, "==", 1);

my $l = Mail::Message::Field->new(Sender =>
 'oijfjslkgjhius2rehtpo2uwpefnwlsjfh2oireuqfqlkhfjowtropqhflksjhflkjhoiewurpq');
my @llines = $k->toString;
cmp_ok(@llines, "==", 1);

my $m = Mail::Message::Field->new(Sender =>
  'roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop, qhflksjhflkj, hoiewurpq');

cmp_ok($m->nrLines, "==", 2);
$m->setWrapLength(35);
cmp_ok($m->nrLines, "==", 3);

my @mlines = $m->toString(72);
cmp_ok(@mlines, "==", 2);
is($mlines[0], "Sender: roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop,\n");
is($mlines[1], " qhflksjhflkj, hoiewurpq\n");