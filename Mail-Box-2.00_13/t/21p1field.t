#!/usr/bin/perl -w
#
# Test processing of header-fields: only single fields, not whole headers.
# This also doesn't cover reading headers from file.
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

BEGIN { plan tests => 15 }

use Mail::Message::Field;
use Mail::Box::Parser::Perl;
use Tools;

# Explictly ask for the Perl parser to fold lines.

Mail::Box::Parser->defaultParserType('Mail::Box::Parser::Perl');

warn "   * Parser in Perl status BETA\n";

#
# Processing of structured lines.
#

my $f = Mail::Message::Field->new('Sender:  B ;  C');
ok($f->name eq 'sender');
ok($f->body eq 'B');
ok($f->comment =~ m/^\s*C\s*/);

# No comment, strip CR LF

my $g = Mail::Message::Field->new("Sender: B\015\012");
ok($g->body eq 'B');
ok(not defined $g->comment);

# Check toString

my $x = $f->toString;
ok($x eq "Sender: B; C\n");

$x = $g->toString;
ok($x eq "Sender: B\n");

# Now check folding.

my $k = Mail::Message::Field->new(Sender => 'short line');
ok($k->toString eq "Sender: short line\n");
my @klines = $k->toString;
ok(@klines==1);

my $l = Mail::Message::Field->new(Sender =>
 'oijfjslkgjhius2rehtpo2uwpefnwlsjfh2oireuqfqlkhfjowtropqhflksjhflkjhoiewurpq');
my @llines = $k->toString;
ok(@llines==1);

my $m = Mail::Message::Field->new(Sender =>
  'roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop, qhflksjhflkj, hoiewurpq');

ok($m->nrLines==1);
$m->setWrapLength(72);
ok($m->nrLines==2);

my @mlines = $m->toString;
ok(@mlines==2);
ok($mlines[0] eq "Sender: roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop,\n");
ok($mlines[1] eq "        qhflksjhflkj, hoiewurpq\n");
