#!/usr/bin/perl
#
# Test processing of header-fields with Mail::Message::Field::Fast.
# Only single fields, not whole headers. This also doesn't cover reading
# headers from file.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);

BEGIN {plan tests => 53}

use Mail::Message::Field::Fast;
use Mail::Address;
use Tools;

warn "   * Mail::Message modules status BETA\n";

#
# Processing unstructured lines.
#

my $a = Mail::Message::Field::Fast->new('A: B  ; C');
ok($a->name eq 'a');
ok($a->body eq 'B  ; C');
ok(not defined $a->comment);

# No folding permitted.

my $bbody = 'B  ; C234290iwfjoj w etuwou   toiwutoi wtwoetuw oiurotu 3 ouwout 2 oueotu2 fqweortu3';
my $b = Mail::Message::Field::Fast->new("A: $bbody");
my @lines = $b->toString(40);

ok(@lines==1);
ok($lines[0] eq "A: $bbody\n");
ok($b->body eq $bbody);

#
# Processing of structured lines.
#

my $f = Mail::Message::Field::Fast->new('Sender:  B ;  C');
ok($f->name eq 'sender');
ok($f->body eq 'B');
ok($f eq 'B');
ok($f->comment =~ m/^\s*C\s*/);

# No comment, strip CR LF

my $g = Mail::Message::Field::Fast->new("Sender: B\015\012");
ok($g->body eq 'B');
ok(not defined $g->comment);

# Separate head and body.

my $h = Mail::Message::Field::Fast->new("Sender", "B\015\012");
ok($h->body eq 'B');
ok(not defined $h->comment);

my $i = Mail::Message::Field::Fast->new('Sender', 'B ;  C');
ok($i->name eq 'sender');
ok($i->body eq 'B');
ok($i->comment =~ m/^\s*C\s*/);

my $j = Mail::Message::Field::Fast->new('Sender', 'B', 'C');
ok($j->name eq 'sender');
ok($j->body eq 'B');
ok($j->comment =~ m/^\s*C\s*/);

# Check toString (for unstructured field, so no folding)

my $k = Mail::Message::Field::Fast->new(A => 'short line');
ok($k->toString eq "A: short line\n");
my @klines = $k->toString;
ok(@klines==1);

my $l = Mail::Message::Field::Fast->new(A =>
 'oijfjslkgjhius2rehtpo2uwpefnwlsjfh2oireuqfqlkhfjowtropqhflksjhflkjhoiewurpq');
my @llines = $k->toString;
ok(@llines==1); 
my $m = Mail::Message::Field::Fast->new(A =>
  'roijfjslkgjhiu, rehtpo2uwpe, fnwlsjfh2oire, uqfqlkhfjowtrop, qhflksjhflkj, hoiewurpq');

my @mlines = $m->toString;
ok(@mlines==1);

my $n  = Mail::Message::Field::Fast->new(A => 7);
my $x = $n + 0;
ok($n ? 1 : 0);
ok($x==7);
ok($n > 6);
ok($n < 8);
ok($n==7);
ok(6 < $n);
ok(8 > $n);

#
# Check gluing addresses
#

my @mb = Mail::Address->parse('me@localhost, you@somewhere.nl');
ok(@mb==2);
my $r  = Mail::Message::Field::Fast->new(Cc => $mb[0]);
ok($r->toString eq "Cc: me\@localhost\n");
$r     = Mail::Message::Field::Fast->new(Cc => \@mb);
ok($r->toString eq "Cc: me\@localhost, you\@somewhere.nl\n");

my $r2 = Mail::Message::Field::Fast->new(Bcc => $r);
ok($r2->toString eq "Bcc: me\@localhost, you\@somewhere.nl\n");

#
# Checking attributes
#

my $charset = 'iso-8859-1';
my $comment = qq(charset="iso-8859-1"; format=flowed);

my $p = Mail::Message::Field::Fast->new("Content-Type: text/plain; $comment");
ok($p->comment eq $comment);
ok($p->body eq 'text/plain');
ok($p->attribute('charset') eq $charset);
ok($p->attribute('format') eq 'flowed');
ok(!defined $p->attribute('boundary'));
ok($p->attribute(charset => 'us-ascii') eq 'us-ascii');
ok($p->attribute('charset') eq 'us-ascii');
ok($p->comment eq 'charset="us-ascii"; format=flowed');
ok($p->attribute(format => 'newform') eq 'newform');
ok($p->comment eq 'charset="us-ascii"; format=newform');
ok($p->attribute(newfield => 'bull') eq 'bull');
ok($p->attribute('newfield') eq 'bull');
ok($p->comment eq 'charset="us-ascii"; format=newform; newfield="bull"');

my $q = Mail::Message::Field::Fast->new('Content-Type: text/plain');
ok($q->toString eq "Content-Type: text/plain\n");
ok($q->attribute(charset => 'iso-10646'));
ok($q->attribute('charset') eq 'iso-10646');
ok($q->comment eq 'charset="iso-10646"');
ok($q->toString eq qq(Content-Type: text/plain; charset="iso-10646"\n));
