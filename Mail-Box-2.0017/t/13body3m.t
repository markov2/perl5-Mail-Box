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
use Tools;

use IO::Scalar;

BEGIN {plan tests => 26}

my $body = Mail::Message::Body::Multipart->new
 ( transfer_encoding => '8bit'
 , boundary          => 'xyz'
 );

ok($body->boundary eq 'xyz');
$body->boundary('part-separator');
ok($body->boundary eq 'part-separator');
ok($body->type eq 'multipart/mixed');

my $h1 = Mail::Message::Head::Complete->new;

my $b1 = Mail::Message::Body::Lines->new
 ( data              => ["p1 l1\n", "p1 l2\n" ]
 , mime_type         => 'text/html'
 , transfer_encoding => '8bit'
 );

ok($b1);
ok($b1->type eq 'text/html');
ok($b1->transferEncoding eq '8bit');
ok($b1->disposition eq 'none');

my $p1 = Mail::Message->new(head => $h1);
ok($p1->body($b1) == $b1);
ok($p1->get('Content-Type') eq 'text/html');
ok($p1->get('Content-Transfer-Encoding') eq '8bit');
ok(!defined $p1->get('Content-Disposition'));

my $h2 = Mail::Message::Head::Complete->new;

my $b2 = Mail::Message::Body::Lines->new
 ( data              => ["p2 l1\n", "p2 l2\n", "p2 l3\n", "p2 l4\n" ]
 , mime_type         => 'text/plain'
 , transfer_encoding => '8bit'
 );

ok($b2);

my $p2 = Mail::Message->new(head => $h2);
ok($p2->body($b2) == $b2);

# Empty multipart

my $fakeout;
my $g = IO::Scalar->new(\$fakeout);
ok($body->parts==0);
$body->print($g);
ok($fakeout eq "--part-separator--\n");

# First attachment

$fakeout = '';

my $newbody = $body->attach($p1);
ok($newbody != $body);
ok($newbody->parts==1);
$newbody->print($g);
ok($fakeout eq <<'EXPECTED');
--part-separator
Content-Type: text/html; charset="us-ascii"
Content-Length: 12
Lines: 2
Content-Transfer-Encoding: 8bit

p1 l1
p1 l2

--part-separator--
EXPECTED

# Second attachment

my $newerbody = $newbody->attach($p2);
ok($newerbody != $newbody);
ok($newerbody->parts==2);

$fakeout = '';
$newerbody->print($g);
ok($fakeout eq <<'EXPECTED');
--part-separator
Content-Type: text/html; charset="us-ascii"
Content-Length: 12
Lines: 2
Content-Transfer-Encoding: 8bit

p1 l1
p1 l2

--part-separator
Content-Type: text/plain; charset="us-ascii"
Content-Length: 24
Lines: 4
Content-Transfer-Encoding: 8bit

p2 l1
p2 l2
p2 l3
p2 l4

--part-separator--
EXPECTED

# Add preamble and epilogue

my $newestbody
   = ref($newerbody)->new
      ( based_on => $newerbody
      , preamble => Mail::Message::Body::Lines->new
         ( data => [ "preamb1\n", "preamb2\n" ]
         , mime_type        => 'text/html'
         , charset          => 'us-ascii'
         , tranfer_encoding => '8bit'
         )
      , epilogue => Mail::Message::Body::Lines
                ->new(data => [ "epilogue\n" ])
      );
ok($newestbody != $newbody);

$fakeout = '';
$newestbody->print($g);
ok($fakeout eq <<'EXPECTED');
preamb1
preamb2
--part-separator
Content-Type: text/html; charset="us-ascii"
Content-Length: 12
Lines: 2
Content-Transfer-Encoding: 8bit

p1 l1
p1 l2

--part-separator
Content-Type: text/plain; charset="us-ascii"
Content-Length: 24
Lines: 4
Content-Transfer-Encoding: 8bit

p2 l1
p2 l2
p2 l3
p2 l4

--part-separator--
epilogue
EXPECTED


# Body to message.  The info on preamble is used to create a whole message
# header.

my $message = Mail::Message->buildFromBody($newestbody,
    From => 'me', To => 'you', Date => 'now');

$fakeout = '';
$message->print($g);
ok($fakeout eq <<'EXPECTED');
From: me
To: you
Date: now
Content-Type: multipart/mixed; boundary="part-separator"
Content-Length: 327
Lines: 24
Content-Transfer-Encoding: 8bit

preamb1
preamb2
--part-separator
Content-Type: text/html; charset="us-ascii"
Content-Length: 12
Lines: 2
Content-Transfer-Encoding: 8bit

p1 l1
p1 l2

--part-separator
Content-Type: text/plain; charset="us-ascii"
Content-Length: 24
Lines: 4
Content-Transfer-Encoding: 8bit

p2 l1
p2 l2
p2 l3
p2 l4

--part-separator--
epilogue
EXPECTED

$message = Mail::Message->buildFromBody($body, From => 'me', To => 'you',
   Date => 'now');

$fakeout = '';
$message->print($g);
ok($fakeout eq <<'EXPECTED');
From: me
To: you
Date: now
Content-Type: multipart/mixed; boundary="part-separator"
Content-Length: 19
Lines: 1
Content-Transfer-Encoding: 8bit

--part-separator--
EXPECTED

$message = Mail::Message->buildFromBody($b1, From => 'me', To => 'you',
   Date => 'now');

$fakeout = '';
$message->print($g);
ok($fakeout eq <<'EXPECTED');
From: me
To: you
Date: now
Content-Type: text/html; charset="us-ascii"
Content-Length: 12
Lines: 2
Content-Transfer-Encoding: 8bit

p1 l1
p1 l2
EXPECTED
