#!/usr/bin/perl
#
# Test the reading from file of message bodies which have their content
# stored in a single string.

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Parser;
use Mail::Message::Body::String;
use Mail::Message::Head;
use Tools;

BEGIN
{   eval 'require Mail::Box::Parser::C';
    if($@)
    {   plan tests => 0;
        exit 0;
    }

    plan tests => 146;
}

Mail::Box::Parser->defaultParserType('Mail::Box::Parser::C');

###
### First carefully read the first message
###

my $parser = Mail::Box::Parser->new(filename  => $src);
ok($parser);

$parser->pushSeparator('From ');
my ($where, $sep) = $parser->readSeparator;
ok($where==0);
ok(defined $sep);
ok(defined $sep && $sep =~ m/^From /);

my $head = Mail::Message::Head->new;
ok(defined $head);

$head->read($parser);
ok($head);

my $length = int $head->get('Content-Length');
ok($length==1280);
my $lines  = int $head->get('Lines');
ok($lines==33);

my $body = Mail::Message::Body::String->new;
$body->read($parser, $head, undef, $length, $lines);
ok(defined $body);

ok($body->size==$length);
my @lines = $body->lines;
ok(@lines==$lines);

#
# Try to read the rest of the folder, with specified content-length
# and lines if available.
#

my @msgs;

push @msgs,  # first message already read.
 { fields => scalar $head->names
 , lines  => $lines
 , size   => $length
 , sep    => $sep
 , subject=> $head->get('subject')
 };

while(1)
{   my ($where, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok = 0;
    $ok++ if $sep =~ m/^From /;

    $head = Mail::Message::Head->new;
    $ok++ if defined $head;

    $head->read($parser);

    my $cl    = $head->get('Content-Length');
    my $li    = $head->get('Lines');
    my $su    = $head->get('Subject');

    $body = Mail::Message::Body::String->new
        ->read($parser, $head, undef, $cl, $li);
    $ok++ if $body;

    my $size  = $body->size;
    my $lines = $body->nrLines;

    $ok++ if !defined $li || $li == $lines;
    $ok++ if !defined $cl || $cl == $size;

    my $msg = 
     { size   => $size
     , lines  => $lines
     , fields => scalar $head->names
     , sep    => $sep
     , subject=> $su
     };

    warn "Failed(1) msg ",scalar @msgs,": ", ($su || '<no subject>'), "\n"
        unless $ok==5;

    push @msgs, $msg;
    ok($ok==5);
}

ok(@msgs==45);
$parser->stop;

# From here on with test 55

###
### Now read the whole folder again, but without help of content-length
### and nor lines.
###

undef $parser;

$parser = Mail::Box::Parser->new(filename => $src);
$parser->pushSeparator('From ');

my $count = 0;
while($sep = $parser->readSeparator)
{   my $ok  = 0;
    my $msg = $msgs[$count++];

    $ok++ if $sep =~ m/^From /;

    $head     = Mail::Message::Head->new->read($parser);
    $ok++ if $head;

    $body = Mail::Message::Body::String->new->read($parser, $head, undef);
    $ok++ if $body;

    my $su    = $head->get('Subject');
    my $size  = $body->size;
    my $lines = $body->nrLines;

    $ok++ if        $size == $msg->{size};
    $ok++ if       $lines == $msg->{lines};
    $ok++ if (!defined $su && !defined $msg->{subject})
                   || $su eq $msg->{subject};
    $ok++ if $head->names == $msg->{fields};
    $ok++ if         $sep eq $msg->{sep};

    warn "Failed(2) ", ($su || '<no subject>'), "\n"
        unless $ok==8;

    ok($ok==8);
}

$parser->stop;

###
### Now read the whole folder again, but with deceiving values for
### content-length and lines
###

undef $parser;

$parser = Mail::Box::Parser->new(filename => $src);
$parser->pushSeparator('From ');

$count = 0;
while(1)
{   my ($where, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok  = 0;
    my $msg = $msgs[$count++];

    $ok++ if $sep =~ m/^From /;

    $head     = Mail::Message::Head->new->read($parser);
    $ok++ if $head;

    $body = Mail::Message::Body::String->new;
    $body->read($parser, $head, undef, $msg->{size}-15, $msg->{lines}-3);
    $ok++ if $body;

    my $su    = $head->get('Subject');
    my $size  = $body->size;
    my $lines = $body->nrLines;

    $ok++ if        $size == $msg->{size};
    $ok++ if       $lines == $msg->{lines};
    $ok++ if (!defined $su && !defined $msg->{subject})
                   || $su eq $msg->{subject};
    $ok++ if $head->names == $msg->{fields};
    $ok++ if         $sep eq $msg->{sep};

    warn "Failed(3) ", ($su || '<no subject>'), "\n"
        unless $ok==8;

    ok($ok==8);
}

