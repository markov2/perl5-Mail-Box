#!/usr/bin/perl -w
#
# Test migration of a message from one folder to an other
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message;
use Mail::Message::Body::String;
use Mail::Message::Body::Lines;
#use Mail::Message::Body::File;
#use Mail::Message::Body::Delayed;

use Mail::Message::Head::Complete;
use Mail::Message::Head::Subset;
use Mail::Message::Head::Partial;
use Mail::Message::Head::Delayed;

use File::Spec;

BEGIN {plan tests => 45}

# Greatest Common Devider of @bodytypes and @headtypes must be 1 to
# get all combinations.

my @bodytypes =
 ( 'Mail::Message::Body::String'
 , 'Mail::Message::Body::Lines'
#, 'Mail::Message::Body::File'
#, 'Mail::Message::Body::Delayed'
 );

my @headtypes =
 ( 'Mail::Message::Head::Complete'
 , 'Mail::Message::Head::Subset'
 , 'Mail::Message::Head::Partial'
 , 'Mail::Message::Head::Delayed'
, 'Mail::Message::Head::Complete'   # gcd => 1
 );

my $inbox = File::Spec->catfile('t', 'mbox.src');
my $parser = Mail::Box::Parser->new(filename  => $inbox)
   or die;

my @messages;

while(1)
{   $parser->pushSeparator('From ');
    my ($where, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok = 0;
    my $headtype = $headtypes[@messages % @headtypes];
    my $head     = $headtype->new->read($parser);
    $ok++ if $head;

    my $bodytype = $bodytypes[@messages % @bodytypes];
    my $body     = $bodytype->new->read($parser);
    $ok++ if $body;

    my $msg      = Mail::Message->new(head => $head, body => $body);
    $ok++ if $msg;

    push @messages, $msg;
    ok($ok==3);
}
