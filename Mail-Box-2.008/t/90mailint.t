#!/usr/bin/perl
#
# Test conversions between Mail::Internet and Mail::Message
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);

use Tools;
use Mail::Message;
use Mail::Message::Convert::MailInternet;

BEGIN
{   eval {require Mail::Internet};
    if($@)
    {   plan tests => 0;
        exit 0;
    }
    plan tests => 21;
}

my $mi = Mail::Internet->new(\*DATA);
ok($mi);

my $convert = Mail::Message::Convert::MailInternet->new;
ok($convert);

#
# Convert Mail::Internet to Mail::Message
#

my $msg = $convert->from($mi);
ok($msg);

my $head = $msg->head;
ok($head);

my @fields = $head->names;
ok(@fields==5);
ok($fields[0] eq 'from');        # order must be preserved
ok($fields[1] eq 'to');
ok($fields[2] eq 'subject');
ok($fields[3] eq 'in-reply-to');
ok($fields[4] eq 'again');

my @from  = $head->get('from');
ok(@from==1);

my @again = $head->get('again');
ok(@again==3);

my $body  = $msg->body;
ok($body);
my @lines = $body->lines;
ok(@lines==6);
ok($lines[-1] eq "that.\n");

#
# Convert message back to a Mail::Internet
#

my $back = $convert->export($msg);
ok($back);
$head    = $back->head;

@fields  = $head->tags;
ok(@fields==5);
ok($head->get('to') eq "the users\n");

@from    = $head->get('from');
ok(@from==1);

@again   = $head->get('again');
ok(@again==3);

$body = $back->body;
ok(@$body==6);

1;

__DATA__
From: mailtools@overmeer.net
To: the users
Subject: use Mail::Box
In-Reply-To: <023984hjlur29420@sruoiu.nl>
Again: repeating header
Again: repeating header again
Again: repeating header and again

Mail::Internet was conceived in 1995, or even earlier, and
written by Graham Barr.  At that time, e-mail was not very
wide-spread (the beginning of WWW) and e-mails where not
poluted by graphics.  Attachments were even so rare that
Mail::Internet cannot handle them: see MIME::Entity for
that.
