#!/usr/bin/perl
#
# Test the reading from file of message bodies which are multiparts
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Message;
use IO::File;

BEGIN {plan tests => 66}

#
# From scalar
#

my $msg1 = Mail::Message->read("Subject: hello world\n\nbody1\nbody2\n");
ok(defined $msg1);
ok(ref $msg1 eq 'Mail::Message');
ok(defined $msg1->head);
ok($msg1->head->isa('Mail::Message::Head'));

my $body1 = $msg1->body;
ok(defined $body1);
ok($body1->isa('Mail::Message::Body'));
ok(!$body1->isDelayed);

ok(@$body1==2);
ok($body1->[0] eq "body1\n");
ok($body1->[1] eq "body2\n");
ok($msg1->subject eq 'hello world');
ok($msg1->messageId);
ok($msg1->get('message-id'));

#
# From ref scalar
#

my $scalar = "Subject: hello world\n\nbody1\nbody2\n";
my $msg2 = Mail::Message->read(\$scalar);
ok(defined $msg2);
ok(ref $msg2 eq 'Mail::Message');
ok(defined $msg2->head);
ok($msg2->head->isa('Mail::Message::Head'));

my $body2 = $msg2->body;
ok(defined $body2);
ok($body2->isa('Mail::Message::Body'));
ok(!$body2->isDelayed);

ok(@$body2==2);
ok($body2->[0] eq "body1\n");
ok($body2->[1] eq "body2\n");
ok($msg2->subject eq 'hello world');
ok($msg2->messageId);
ok($msg2->get('message-id'));

#
# From array
#

my $array = [ "Subject: hello world\n", "\n", "body1\n", "body2\n" ];
my $msg3 = Mail::Message->read($array);
ok(defined $msg3);
ok(ref $msg3 eq 'Mail::Message');
ok(defined $msg3->head);
ok($msg3->head->isa('Mail::Message::Head'));

my $body3 = $msg3->body;
ok(defined $body3);
ok($body3->isa('Mail::Message::Body'));
ok(!$body3->isDelayed);

ok(@$body3==2);
ok($body3->[0] eq "body1\n");
ok($body3->[1] eq "body2\n");
ok($msg3->subject eq 'hello world');
ok($msg3->messageId);
ok($msg3->get('message-id'));

#
# From file glob
#

open OUT, '>', 'tmp' or die $!;
print OUT $scalar;
close OUT;

open IN, '<', 'tmp' or die $!;
my $msg4 = Mail::Message->read(\*IN);
close IN;

ok(defined $msg4);
ok(ref $msg4 eq 'Mail::Message');
ok(defined $msg4->head);
ok($msg4->head->isa('Mail::Message::Head'));

my $body4 = $msg4->body;
ok(defined $body4);
ok($body4->isa('Mail::Message::Body'));
ok(!$body4->isDelayed);

ok(@$body4==2);
ok($body4->[0] eq "body1\n");
ok($body4->[1] eq "body2\n");
ok($msg4->subject eq 'hello world');
ok($msg4->messageId);
ok($msg4->get('message-id'));


#
# From file handle
#

open OUT, '>', 'tmp' or die $!;
print OUT $scalar;
close OUT;

my $in = IO::File->new('tmp', 'r');
ok(defined $in);
my $msg5 = Mail::Message->read($in);
$in->close;

ok(defined $msg5);
ok(ref $msg5 eq 'Mail::Message');
ok(defined $msg5->head);
ok($msg5->head->isa('Mail::Message::Head'));

my $body5 = $msg5->body;
ok(defined $body5);
ok($body5->isa('Mail::Message::Body'));
ok(!$body5->isDelayed);

ok(@$body5==2);
ok($body5->[0] eq "body1\n");
ok($body5->[1] eq "body2\n");
ok($msg5->subject eq 'hello world');
ok($msg5->messageId);
ok($msg5->get('message-id'));

unlink 'tmp';
