#!/usr/bin/perl -w
#
# Test processing of multipart message bodies.
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Head::Complete;

use IO::Scalar;

BEGIN {plan tests => 7}

my $body = Mail::Message::Body::Multipart->new;
$body->boundary('part-separator');

my $h1 = Mail::Message::Head::Complete->new;
$h1->add('Content-Type' => 'text/plain');
my $b1 = Mail::Message::Body::Lines->new(data => ["p1 l1\n", "p1 l2\n" ]);
my $p1 = Mail::Message->new(head => $h1, body => $b1);

my $h2 = Mail::Message::Head::Complete->new;
$h2->add('Content-Type' => 'text/plain');
my $b2 = Mail::Message::Body::Lines->new(data =>
    ["p2 l1\n", "p2 l2\n", "p2 l3\n", "p2 l4\n" ]);
my $p2 = Mail::Message->new(head => $h2, body => $b2);

# Empty multipart

my $fakeout;
my $g = IO::Scalar->new(\$fakeout);
ok($body->parts==0);
$body->print($g);
ok($fakeout eq "--part-separator--\n");

# First attachment

$fakeout = '';

$body->attach($p1);
ok($body->parts==1);
$body->print($g);
ok($fakeout eq <<'EXPECTED');
--part-separator
Content-Type: text/plain

p1 l1
p1 l2

--part-separator--
EXPECTED

# Second attachment

$body->attach($p2);
ok($body->parts==2);

$fakeout = '';
$body->print($g);
ok($fakeout eq <<'EXPECTED');
--part-separator
Content-Type: text/plain

p1 l1
p1 l2

--part-separator
Content-Type: text/plain

p2 l1
p2 l2
p2 l3
p2 l4

--part-separator--
EXPECTED

# Add preamble and epilogue

$body->preamble(Mail::Message::Body::Lines
                ->new(data => [ "preamb1\n", "preamb2\n" ]));

$body->epilogue(Mail::Message::Body::Lines
                ->new(data => [ "epilogue\n" ]));

$fakeout = '';
$body->print($g);
ok($fakeout eq <<'EXPECTED');
preamb1
preamb2
--part-separator
Content-Type: text/plain

p1 l1
p1 l2

--part-separator
Content-Type: text/plain

p2 l1
p2 l2
p2 l3
p2 l4

--part-separator--
epilogue
EXPECTED
