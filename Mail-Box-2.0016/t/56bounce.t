#!/usr/bin/perl -w
#
# Test the creation of bounce messages
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message;
use Mail::Message::Head;
use Mail::Message::Body::Lines;
use Mail::Message::Construct;

use Tools;
use IO::Scalar;

BEGIN {plan tests => 2}

#
# First produce a message to reply to.
#

my $head = Mail::Message::Head->build
 ( To      => 'me@example.com (Me the receiver)'
 , From    => 'him@somewhere.else.nl (Original Sender)'
 , Cc      => 'the.rest@world.net'
 , Subject => 'Test of Bounce'
 , Date    => 'Wed, 9 Feb 2000 15:44:05 -0500'
 , 'Content-Something' => 'something'
 );

my $body = Mail::Message::Body::Lines->new
  ( mime_type => 'text/plain'
  , data      => <<'TEXT'
First line of orig message.
Another line of message.
TEXT
  );

my $msg  = Mail::Message->new(head => $head);
$msg->body($body);
ok(defined $msg);

#
# Create a bounce
#

my $bounce = $msg->bounce
 ( To         => 'new@receivers.world'
 , From       => 'I was between'
 , 'Reply-To' => 'no-one'
 , Date       => 'Fri, 7 Dec 2001 15:44:05 -0100'
 , 'Message-ID' => '2394802'
 );

my $filedata;
my $file = IO::Scalar->new(\$filedata);
$bounce->print($file);

#print "#$filedata#";

ok($filedata eq <<'EXPECTED')
To: me@example.com (Me the receiver)
From: him@somewhere.else.nl (Original Sender)
Cc: the.rest@world.net
Subject: Test of Bounce
Date: Wed, 9 Feb 2000 15:44:05 -0500
Content-Something: something
Content-Type: text/plain; charset="us-ascii"
Content-Length: 53
Lines: 2
Content-Transfer-Encoding: 8bit
Resent-From: I was between
Resent-To: new@receivers.world
Resent-Date: Fri, 7 Dec 2001 15:44:05 -0100
Resent-Reply-To: no-one
Resent-Message-ID: <2394802>

First line of orig message.
Another line of message.
EXPECTED
