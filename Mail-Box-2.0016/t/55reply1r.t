#!/usr/bin/perl -w
#
# Test the creation of reply messages
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message;
use Mail::Message::Head;
use Mail::Message::Body::Lines;
use Mail::Message::Construct;
use Tools;

BEGIN {plan tests => 22}

#
# First produce a message to reply to.
#

my $head = Mail::Message::Head->new;
$head->add(To   => 'me@example.com (Me the receiver)');
$head->add(From => 'him@somewhere.else.nl (Original Sender)');
$head->add(Cc   => 'the.rest@world.net');
$head->add(Subject => 'Test of Reply');
$head->add(Skip => 'Do not take this line');
$head->add(Date => 'Wed, 9 Feb 2000 15:44:05 -0500');
$head->add('Content-Something' => 'something');

my ($text, $sig) = (<<'TEXT', <<'SIG');
First line of orig message.
Another line of message.
TEXT
--
And this is the signature
which
has
a
few lines
too
SIG

my @lines = split /(?<=\n)/, $text.$sig;
my $body = Mail::Message::Body::Lines->new
  ( mime_type => 'text/plain'
  , data      => \@lines
  );

ok(defined $body);

my $msg  = Mail::Message->new(head => $head);
$msg->body($body);

ok(defined $msg);

#
# Create a simple reply
#

my $reply = $msg->reply
  ( strip_signature => undef
  , prelude         => undef
  , quote           => undef
  );

ok(defined $reply);
ok($reply->isa('Mail::Message'));
ok($reply->body==$msg->body);

ok(  $reply->head->get('to') eq $msg->head->get('from'));
ok($reply->head->get('from') eq $msg->head->get('to'));
ok(!defined $reply->head->get('cc'));
ok(!defined $reply->head->get('skip'));
ok(!defined $reply->head->get('content-something'));
#$reply->head->print(\*STDERR);

#warn $reply->body->string;
ok($reply->body->string eq $text.$sig);

#
# Create a complicated reply
#

my $postlude = Mail::Message::Body::Lines->new
  ( data => [ "added to the end\n", "two lines\n" ]
  );

$reply = $msg->reply
  ( group_reply => 1
  , quote       => '] '
  , postlude    => $postlude
  );

ok($reply->body!=$msg->body);
ok(  $reply->head->get('to') eq $msg->head->get('from'));
ok($reply->head->get('from') eq $msg->head->get('to'));
ok(  $reply->head->get('cc') eq $msg->head->get('cc'));
ok(!defined $reply->head->get('skip'));

#$reply->body->print;
ok($reply->body->string eq <<'EXPECT');
On Wed Feb  9 20:44:05 2000, Original Sender wrote:
] First line of orig message.
] Another line of message.
added to the end
two lines
EXPECT

#
# Another complicated reply
#

$reply = $msg->reply
  ( group_reply => 0
  , quote       => sub {chomp; "> ".reverse."\n"}
  , postlude    => $postlude
  );

ok(  $reply->head->get('to') eq $msg->head->get('from'));
ok($reply->head->get('from') eq $msg->head->get('to'));
ok(!defined $reply->head->get('cc'));
ok(!defined $reply->head->get('skip'));

#$reply->body->print;
ok($reply->body->string eq <<'EXPECT');
On Wed Feb  9 20:44:05 2000, Original Sender wrote:
> .egassem giro fo enil tsriF
> .egassem fo enil rehtonA
added to the end
two lines
EXPECT
