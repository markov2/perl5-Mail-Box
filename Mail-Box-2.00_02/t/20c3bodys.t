#!/usr/bin/perl -w
#
# Test the reading from file of message bodies which have their content
# stored in a single string.

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Parser;
use Mail::Message::Body::String;
use Mail::Message::Head;

use IO::Scalar;
use File::Spec;

BEGIN
{   eval 'require Mail::Box::Parser::C';
    if($@)
    {   plan tests => 0;
        exit 0;
    }

    plan tests => 30;
}

my $inbox = File::Spec->catfile('t', 'mbox.src');

my $parser = Mail::Box::Parser->new
  ( filename  => $inbox
  , seperator => 'FROM'
  );

ok($parser);

my $head = Mail::Message::Head->new;
ok(defined $head);

$head->read($parser);
ok($head);

my $body = Mail::Message::Body::String->new;
ok(defined $body);

my $length = int $head->get('Content-Length');
ok($length==1280);

$body->read($parser, $length);
