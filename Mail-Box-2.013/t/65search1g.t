#!/usr/bin/perl

#
# Test searching with grep
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Tools;
use Mail::Box::Manager;
use Mail::Box::Search::Grep;

use IO::Scalar;

BEGIN {plan tests => 56}

my $mgr    = Mail::Box::Manager->new;

my $folder = $mgr->open($cpy);
ok(defined $folder);

#
# Simple search in body
#

my $output;
my $fh    = IO::Scalar->new(\$output) or die $!;
my $oldfh = select $fh;

my $grep1  = Mail::Box::Search::Grep->new
 ( match   => 'However'
 , in      => 'BODY'
 , details => 'PRINT'
 );

$grep1->search($folder);
$fh->close;
select $oldfh;

ok($output eq <<'EXPECTED');
t/mbox.cpy, message 7: Resize with Transparency
   21: However, ImageMagick (ImageMagick 4.2.7, PerlMagick 4.27 on Linux)
t/mbox.cpy, message 36: Re: core dump in simple ImageMagick example
   38: However, it is only reproduceable when this statement is included in
t/mbox.cpy, message 39: Re: core dump in simple ImageMagick example
    4: > However, it is only reproduceable when this statement is included in
EXPECTED

undef $grep1;

#
# search in head with limit
#

undef $output;
$fh    = IO::Scalar->new(\$output) or die $!;
select $fh;

my $grep2  = Mail::Box::Search::Grep->new
 ( match   => 'atcmpg'
 , in      => 'HEAD'
 , limit   => -4
 , details => 'PRINT'
 );

my @m2 = $grep2->search($folder);
$fh->close;
select $oldfh;

ok(@m2==4);

my $last = shift @m2;
foreach (@m2)
{   ok($last->seqnr < $_->seqnr);
    $last = $_;
}

# messages are reversed ordered here, but in order returned: looking
# backwards in the folder file.

ok($output eq <<'EXPECTED');
t/mbox.cpy, message 42: Font metrics
  Received: from ns.ATComputing.nl (ns.ATComputing.nl [195.108.229.25])
          by atcmpg.ATComputing.nl (8.9.0/8.9.0) with ESMTP id TAA26427
          for <markov@ATComputing.nl>; Wed, 4 Oct 2000 19:56:00 +0200
          (MET DST)
t/mbox.cpy, message 41: Core Dump on ReadImage
  Received: from ns.ATComputing.nl (ns.ATComputing.nl [195.108.229.25])
          by atcmpg.ATComputing.nl (8.9.0/8.9.0) with ESMTP id WAA14913
          for <markov@ATComputing.nl>; Tue, 1 Aug 2000 22:37:13 +0200
          (MET DST)
t/mbox.cpy, message 40: Re: Core Dump on ReadImage
  Message-ID: <20000807113844.A22119@atcmpg.ATComputing.nl>
t/mbox.cpy, message 39: Re: core dump in simple ImageMagick example
  Received: from ns.ATComputing.nl (ns.ATComputing.nl [195.108.229.25])
          by atcmpg.ATComputing.nl (8.9.0/8.9.0) with ESMTP id NAA29434
          for <markov@ATComputing.nl>; Wed, 26 Jul 2000 13:46:33 +0200
          (MET DST)
  References: <397C6C6B.989E4BB2@catchword.com>
          <20000726133231.G25170@atcmpg.ATComputing.nl>
EXPECTED

undef $grep2;

#
# Test regexp search
#

my @hits;
my $grep3  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/
 , in      => 'MESSAGE'
 , details => \@hits
 );

my @m3 = $grep3->search($folder);
ok(@m3==23);
ok(@hits==59);

$last = shift @m3;
my %m3 = ($last->seqnr => 1);
foreach (@m3)   # in order?
{   ok($last->seqnr < $_->seqnr);
    $m3{$_->seqnr}++;
    $last = $_;
}
ok(keys %m3==23);

my %h3 = map { ($_->{message}->seqnr => 1) } @hits;
ok(keys %h3==23);

undef $grep3;

#
# Test regexp search with case-ignore
#

@hits = ();
my $grep4  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'MESSAGE'
 , details => \@hits
 );

my @m4 = $grep4->search($folder);
ok(@m4==26);
ok(@hits==98);

undef $grep4;

#
# Test regexp search with case-ignore and some deleted messages
#

@hits = ();
$folder->message($_)->delete(1) for 3, 6, 8, 9, 11, 13, 23, 33;

my $grep5  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'MESSAGE'
 , details => \@hits
 );

my @m5 = $grep5->search($folder);
ok(@m5==23);
ok(@hits==95);

undef $grep5;

# Include-deleted

@hits = ();
my $grep6  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'MESSAGE'
 , deleted => 1
 , details => \@hits
 );

my @m6 = $grep6->search($folder);
ok(@m6==26);
ok(@hits==98);

undef $grep6;

# only in header

@hits = ();
my $grep7  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'HEAD'
 , details => \@hits
 );

my @m7 = $grep7->search($folder);
ok(@m7==10);
ok(@hits==24);

undef $grep7;

# only in body

@hits = ();
my $grep8  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'BODY'
 , details => \@hits
 );

my @m8 = $grep8->search($folder);
ok(@m8==23);
ok(@hits==71);

ok($grep8->search($folder)==23);

undef $grep8;

# only test for match: stops at first hit

my $grep9  = Mail::Box::Search::Grep->new
 ( match   => qr/ImageMagick/i
 , in      => 'BODY'
 );

ok($grep9->search($folder)==1);

undef $grep9;

#
# Search in thread
#

undef $output;
$fh   = IO::Scalar->new(\$output) or die $!;
select $fh;

my $grep10  = Mail::Box::Search::Grep->new
 ( match   => 'ImageMagick'
 , in      => 'BODY'
 , details => 'PRINT'
 );

my $t     = $mgr->threads($folder);
my $start = $t->threadStart($folder->message(24));  #isa multipart
my @msgs  = $start->threadMessages;

ok(@msgs==2);
ok($grep10->search($start));

ok($output eq <<'EXPECTED');
t/mbox.cpy, message 25: Re: your mail
   13: Are you using ImageMagick 5.2.0?  When I used the script I sent the
t/mbox.cpy, message 24: Re: your mail
p  19: > Are you using ImageMagick 5.2.0?  When I used the script I sent the
EXPECTED

my @m10 = $grep10->search(\@msgs);
ok(@m10==2);
ok($m10[0]==$msgs[0]);
ok($m10[1]==$msgs[1]);

$fh->close;
select $oldfh;

undef $grep10;

# Without multipart

undef $output;
$fh   = IO::Scalar->new(\$output) or die $!;
select $fh;

my $grep11  = Mail::Box::Search::Grep->new
 ( match      => 'ImageMagick'
 , in         => 'BODY'
 , details    => 'PRINT'
 , multiparts => 0
 );

my @m11 = $grep11->search($start);
ok(@m11==1);

$fh->close;
select $oldfh;

ok($output eq <<'EXPECTED');
t/mbox.cpy, message 25: Re: your mail
   13: Are you using ImageMagick 5.2.0?  When I used the script I sent the
EXPECTED

undef $grep11;

#
# Check search in encoded part
#

my $msg = $folder->messageId('8172.960997992@mystic');
ok($msg);

undef $output;
$fh   = IO::Scalar->new(\$output) or die $!;
select $fh;

my $grep12  = Mail::Box::Search::Grep->new
 ( match      => 'pointsize'
 , in         => 'MESSAGE'
 , binaries   => 1
 , details    => 'PRINT'
 );

my @m12 = $grep12->search($msg);
ok(@m12==1);

$fh->close;
select $oldfh;

ok($output eq <<'EXPECTED');
t/mbox.cpy, message 19: 
p  12:       , pointsize => $poinsize
EXPECTED

undef $grep12;
