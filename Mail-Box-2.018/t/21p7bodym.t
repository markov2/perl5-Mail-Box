#!/usr/bin/perl
#
# Test the reading from file of message bodies which are multiparts
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Mail::Box::Parser::Perl;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;
use Mail::Message::Head;
use Tools;

BEGIN {plan tests => 11}

my $getbodytype = sub { 'Mail::Message::Body::Lines' };

###
### First pass through all messages, with correct data, if available
###

my $parser = Mail::Box::Parser::Perl->new(filename  => $src);
ok($parser);

$parser->pushSeparator('From ');

my (@msgs, $msgnr);

while(1)
{   my (undef, $sep) = $parser->readSeparator;
    last unless $sep;

    $msgnr++;

    my $ok = 0;
    $ok++ if $sep =~ m/^From /;

    my $head = Mail::Message::Head->new;
    $ok++ if defined $head;

    $head->read($parser);

    my $cl    = $head->get('Content-Length');
    my $li    = $head->get('Lines');

    unless($head->isMultipart)
    {   # Skip non-multipart
        Mail::Message::Body::Lines->new->read($parser, $head, undef, $cl, $li);
        next;
    }

    my $body = Mail::Message::Body::Multipart->new
        ->read($parser, $head, $getbodytype, $cl, $li);
    $ok++ if defined $body;

    my $mp = $head->get('Content-Type')->comment;
    if($mp =~ m/['"](.*?)["']/)
    {   $body->boundary($1);
    }

    my $size  = $body->size;
    my $lines = $body->nrLines;
    my $su    = $head->get('Subject');

    $ok++ if $body->isMultipart || !defined $li || $li == $lines;
    $ok++ if $body->isMultipart || !defined $cl || $cl == $size;

    my $msg = 
     { size   => $size
     , lines  => $lines
     , fields => scalar $head->names
     , sep    => $sep
     , subject=> $su
     };

    warn "Failed(1) msg $msgnr, ok=$ok: ", ($su || '<no subject>'), "\n"
        unless $ok==5;

    push @msgs, $msg;

    ok($ok==5);
}

ok(@msgs==3);
$parser->stop;

# From here on with test 55

###
### Now read the whole folder again, but without help of content-length
### and nor lines.
###

undef $parser;

$parser = Mail::Box::Parser::Perl->new(filename => $src);
$parser->pushSeparator('From ');

my $count = 0;
while(1)
{   my (undef, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok   = 0;

    $ok++ if $sep =~ m/^From /;

    my $head = Mail::Message::Head->new->read($parser);
    $ok++ if defined $head;

    unless($head->isMultipart)
    {   # Skip non-multipart
        Mail::Message::Body::Lines->new->read($parser, $head, undef);
        next;
    }

    my $msg  = $msgs[$count++];
    my $body = Mail::Message::Body::Multipart->new
        ->read($parser, $head, $getbodytype);
    $ok++ if defined $body;

    my $mp = $head->get('Content-Type')->comment;
    if($mp =~ m/['"](.*?)["']/)
    {   $body->boundary($1);
    }

    my $size  = $body->size;
    my $lines = $body->nrLines;
    my $su    = $head->get('Subject');

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

$parser = Mail::Box::Parser::Perl->new(filename => $src);
$parser->pushSeparator('From ');

$count = 0;
while(1)
{   my (undef, $sep) = $parser->readSeparator;
    last unless $sep;

    my $ok   = 0;

    $ok++ if $sep =~ m/^From /;

    my $head = Mail::Message::Head->new->read($parser);
    $ok++ if defined $head;

    unless($head->isMultipart)
    {   # Skip non-multipart
        Mail::Message::Body::Lines->new->read($parser, $head, undef);
        next;
    }

    my $msg  = $msgs[$count++];
    my $body = Mail::Message::Body::Multipart->new->read($parser, $head,
        $getbodytype, $msg->{size}-15, $msg->{lines}-3);

    $ok++ if defined $body;

    my $mp = $head->get('Content-Type')->comment;
    if($mp =~ m/['"](.*?)["']/)
    {   $body->boundary($1);
    }

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

