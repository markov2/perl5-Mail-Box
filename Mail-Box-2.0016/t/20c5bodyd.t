#!/usr/bin/perl -w
#
# Test the reading from file of message bodies which have their content
# stored in a single Lines.

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Box::Parser;
use Mail::Box::Mbox::Message;
use Mail::Message::Body::Delayed;
use Mail::Message::Head;
use Mail::Message;
use Tools;

use File::Spec;

BEGIN
{   eval 'require Mail::Box::Parser::C';
    if($@)
    {   plan tests => 0;
        exit 0;
    }

    plan tests => 144;
}

Mail::Box::Parser->defaultParserType('Mail::Box::Parser::C');
my $inbox = File::Spec->catfile('t', 'mbox.src');

my $dummy = Mail::Message->new;

###
### First carefully read the first message
###

my $parser = Mail::Box::Parser->new(filename  => $inbox);
ok($parser);

$parser->pushSeparator('From ');
my ($where, $sep) = $parser->readSeparator;
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

my $body = Mail::Message::Body::Delayed->new(message => $dummy);
$body->read($parser, $head, undef, $length, $lines);
ok(defined $body);

ok($body->guessSize==$length);

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
{   my (undef, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok = 0;
    $ok++ if $sep =~ m/^From /;

    $head = Mail::Message::Head->new;
    $ok++ if defined $head;

    $head->read($parser);

    my $cl    = $head->get('Content-Length');
    my $li    = $head->get('Lines');
    my $su    = $head->get('Subject');

    $body = Mail::Message::Body::Delayed->new(message => $dummy)
        ->read($parser, $head, undef, $cl, $li);
    $ok++ if $body;

    my $size  = $body->guessSize;

    $ok++ if !defined $cl || $cl == $size;

    my $msg = 
     { size   => $size
     , fields => scalar $head->names
     , sep    => $sep
     , subject=> $su
     };

    warn "Failed ",scalar @msgs,": ", ($su || '<no subject>'), "\n"
        unless $ok==4;

    push @msgs, $msg;

    ok($ok==4);
}

ok(@msgs==45);
$parser->stop;

# From here on with test 55

###
### Now read the whole folder again, but without help of content-length
### and nor lines.
###

undef $parser;

$parser = Mail::Box::Parser->new(filename => $inbox);
$parser->pushSeparator('From ');

my $count = 0;
while(1)
{   my (undef, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok  = 0;
    my $msg = $msgs[$count++];

    $ok++ if $sep =~ m/^From /;

    $head     = Mail::Message::Head->new->read($parser);
    $ok++ if $head;

    $body = Mail::Message::Body::Delayed->new(message => $dummy)
       ->read($parser, $head, undef);
    $ok++ if $body;

    my $su    = $head->get('Subject');
    my $size  = $body->guessSize;
    my $lines = $msg->{lines} = $body->nrLines;

    $ok++ if        $size == $msg->{size};
    $ok++ if (!defined $su && !defined $msg->{subject})
                   || $su eq $msg->{subject};
    $ok++ if $head->names == $msg->{fields};
    $ok++ if         $sep eq $msg->{sep};

    warn "Failed(2) ", ($su || '<no subject>'), "\n"
        unless $ok==7;

    ok($ok==7);
}

$parser->stop;

###
### Now read the whole folder again, but with deceiving values for
### content-length and lines
###

undef $parser;

$parser = Mail::Box::Parser->new(filename => $inbox);
$parser->pushSeparator('From ');

$count = 0;
while($sep = $parser->readSeparator)
{   my $ok  = 0;
    my $msg = $msgs[$count++];

    $ok++ if $sep =~ m/^From /;

    $head     = Mail::Message::Head->new->read($parser);
    $ok++ if $head;

    $body = Mail::Message::Body::Delayed->new(message => $dummy);
    $body->read($parser, $head, undef, $msg->{size}-15, $msg->{lines}-3);
    $ok++ if $body;

    my $su    = $head->get('Subject');
    my $size  = $body->guessSize;
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

