#!/usr/bin/perl
#
# Test the creation of forwarded messages
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Message;
use Mail::Message::Head;
use Mail::Message::Body::Lines;
use Mail::Message::Construct;

use Mail::Address;

BEGIN {plan tests => 16}

#
# First produce a message to forward to.
#

my $head = Mail::Message::Head->build
 ( To   => 'me@example.com (Me the receiver)'
 , From => 'him@somewhere.else.nl (Original Sender)'
 , Cc   => 'the.rest@world.net'
 , Subject => 'Test of forward'
 , Date => 'Wed, 9 Feb 2000 15:44:05 -0500'
 , 'Content-Something' => 'something'
 );

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
# Create a simple forward
#

my $forward = $msg->forward
  ( strip_signature => undef
  , prelude         => undef
  , postlude        => undef
  , quote           => undef
  , To              => 'dest@example.com (New someone)'
  );

ok(defined $forward);
ok($forward->isa('Mail::Message'));
my @f = $forward->body->string;
my @g = $msg->body->string;
ok(@f eq @g);
#$forward->print(\*STDERR);

#
# Create a real forward
#

my $dest = 'dest@test.org (Destination)';
$forward = $msg->forward
  ( quote    => '] '
  , To       => $dest
  );

ok($forward->body!=$msg->body);
ok(  $forward->head->get('to') eq $dest);
ok($forward->head->get('from') eq $msg->head->get('to'));
ok(! defined $forward->head->get('cc'));

#$forward->print;
ok($forward->body->string eq <<'EXPECT');
---- BEGIN forwarded message
From: him@somewhere.else.nl (Original Sender)
To: me@example.com (Me the receiver)
Cc: the.rest@world.net
Date: Wed, 9 Feb 2000 15:44:05 -0500

] First line of orig message.
] Another line of message.
---- END forwarded message
EXPECT

#
# Another complicated forward
#

my $postlude = Mail::Message::Body::Lines->new
  ( data => [ "added to the end\n", "two lines\n" ]
  );

$forward = $msg->forward
  ( group_forward => 0
  , quote       => sub {chomp; "> ".reverse."\n"}
  , prelude     => "From me!\n"
  , postlude    => $postlude
  , Cc          => 'xyz'
  , Bcc         => Mail::Address->new('username', 'user@example.com')
  , To          => $dest
  );

ok(  $forward->head->get('to') eq $dest);
ok($forward->head->get('from') eq $msg->head->get('to'));
ok($forward->head->get('cc') eq 'xyz');
ok(!defined $forward->head->get('skip'));
ok($forward->head->get('bcc') eq 'username <user@example.com>');

#$forward->print;
ok($forward->body->string eq <<'EXPECT');
From me!
> .egassem giro fo enil tsriF
> .egassem fo enil rehtonA
added to the end
two lines
EXPECT
