#!/usr/bin/perl -w
#
# Test processing of header-fields: only single fields, not whole headers.
# This also doesn't cover reading headers from file.
#

use Test;
use strict;
use lib '/home/markov/fake';

BEGIN {plan tests => 27}

use Mail::Message::Field;

warn "   * Mail::Message modules status ALPHA\n";

#
# Processing unstructured lines.
#

my $a = Mail::Message::Field->new('A: B  ; C');
ok($a->name eq 'a');
ok($a->body eq 'B  ; C');
ok(not defined $a->comment);

# No folding permitted.

my $bbody = 'B  ; C234290iwfjoj w etuwou   toiwutoi wtwoetuw oiurotu 3 ouwout 2 oueotu2 fqweortu3';
my $b = Mail::Message::Field->new("A: $bbody");
my @lines = $b->toString(40);

ok(@lines==1);
ok($lines[0] eq "A: $bbody");
ok($b->body eq $bbody);

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

# Separate head and body.

my $h = Mail::Message::Field->new("Sender", "B\015\012");
ok($h->body eq 'B');
ok(not defined $h->comment);

my $i = Mail::Message::Field->new('Sender', 'B ;  C');
ok($i->name eq 'sender');
ok($i->body eq 'B');
ok($i->comment =~ m/^\s*C\s*/);

my $j = Mail::Message::Field->new('Sender', 'B', 'C');
ok($j->name eq 'sender');
ok($j->body eq 'B');
ok($j->comment =~ m/^\s*C\s*/);

# Check toString

my $x = $f->toString;
ok($x eq 'Sender: B; C');

$x = $g->toString;
ok($x eq 'Sender: B');

# Now check folding.

my $k = Mail::Message::Field->new(Sender => 'short line');
ok($k->toString eq 'Sender: short line');
my @klines = $k->toString;
ok(@klines==1);

my $l = Mail::Message::Field->new(Sender =>
 'oijfjslkgjhius2rehtpo2uwpefnwlsjfh2oireuqfqlkhfjowtropqhflksjhflkjhoiewurpq');
my @llines = $k->toString;
ok(@llines==1);

my $m = Mail::Message::Field->new(Sender =>
  'roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop, qhflksjhflkj, hoiewurpq');

my @mlines = $m->toString;
ok(@mlines==2);
ok($mlines[0] eq 'Sender: roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop,');
ok($mlines[1] eq '        qhflksjhflkj, hoiewurpq');
