#!/usr/bin/perl
#
# Test processing of field attributes in their most expensive implementation!
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

package Mail::Message::Field::Attribute;   # define package name
package main;

BEGIN {
   if($] < 5.007003)
   {   plan skip_all => "Requires module Encode which requires Perl 5.7.3";
       exit 0;
   }

   eval 'require Mail::Message::Field::Attribute';
   if($@)
   {
warn $@;
       plan skip_all => 'Extended attributes not available (install Encode?)';
       exit 0;
   }
   else
   {   plan tests => 91;
   }
}

use Tools;

my $mmfa = 'Mail::Message::Field::Attribute';

#
# Test construction
#

my $a = $mmfa->new('a');
isa_ok($a, $mmfa);
is($a->name, 'a');
ok(defined $a,                           "object a creation");
ok(!defined $a->charset,                 "charset undef");
ok(!defined $a->language,                "language undef");

my $b = $mmfa->new('b', charset => 'iso-8859-15', language => 'nl-BE');
is($b->name, 'b');
ok(defined $a,                           "object b creation");
is($b->charset, 'iso-8859-15',           "charset pre-set");
is($b->language, 'nl-BE',                "language pre-set");

#
# Test situations without encoding or continuations
#

is($a->value, '');

ok($a->addComponent('a=test-any-field'), "simple component");
is($a->value, "test-any-field",          "simple component set");
is($a->string, "; a=test-any-field",     "simple component string");
my $s = ($a->string)[0];
is($s, "a=test-any-field",               "simple component string");

ok($a->addComponent('a="test-any\"-field"'), "dq component");
is($a->value, 'test-any"-field',         "dq component set");
is($a->string, "; a=\"test-any\\\"-field\"", "dq component string");
$s = ($a->string)[0];
is($s, 'a="test-any\"-field"',           "dq component string");

ok($a->addComponent("a='test-any\\'-field'"), "sq component");
is($a->value, "test-any'-field",         "sq component set");
is($a->string, "; a='test-any\\'-field'","sq component string");
$s = ($a->string)[0];
is($s, "a='test-any\\'-field'",           "sq component string");

#
# Tests for decoding without continuations
#

my $c = $mmfa->new('c', use_continuations => 0);
isa_ok($c, $mmfa,                         "Construction of c");

ok($c->addComponent("c*=''abc"),          "c without spec");
ok(! defined $c->charset);
ok(! defined $c->language);
is($c->value, 'abc');

ok($c->addComponent("c*=us-ascii''abc"),  "c with charset");
is($c->charset, 'us-ascii');
ok(! defined $c->language);
is($c->value, 'abc');

ok($c->addComponent("c*='en'abc"),        "c with language");
ok(! defined $c->charset);
is($c->language, 'en');
is($c->value, 'abc');

ok($c->addComponent("c*=us-ascii'en'abc"),"c with both");
is($c->charset, 'us-ascii');
is($c->language, 'en');
is($c->value, 'abc');

#
# Tests for encoding without continuations
#

my $d = $mmfa->new('d', charset => 'iso-8859-1', use_continuations => 0);
ok($d,                                     "Created d");
is($d->value, '');
is($d->value('abc'), 'abc');
is($d->value, 'abc');

my @s = $d->string;
cmp_ok(scalar @s, '==', 1);
is($s[0], "d*=iso-8859-1''abc"); 
is($d->string, "; d*=iso-8859-1''abc");

my @mq =
 ( 'JHKU(@*#&$ASK(@CKH*#@DHKAFsfdsk\"{PO{}[2348*(&(234897(&(ws:\"<?>:LK:K@@'
 , '4279234897 '
 );

my $m = join '', @mq;
$m =~ s/\\"/"/g;

my @me =
 ( 'JHKU%28%40%2A%23%26%24ASK%28%40CKH%2A%23%40DHKAFsfdsk%22%7B'
 , 'PO%7B%7D%5B2348%2A%28%26%28234897%28%26%28ws%3A%22%3C%3F%3E%3ALK%3AK%40'
 , '%404279234897%20'
 );
my $me = join '', @me;

is($d->value($m), $m);
is($d->value, $m);
@s = $d->string;
cmp_ok(scalar @s, '==', 1);
is($s[0], "d*=iso-8859-1''$me"); 
is($d->string, "; d*=iso-8859-1''$me");

$d->addComponent("d*=iso-8859-2''$me"); 
is($d->charset, 'iso-8859-2');
ok(! defined $d->language);
is($d->value, $m);

#
# Tests for encoding with continuations
#

my $e = $mmfa->new('e', charset => 'iso-8859-1', use_continuations => 1);
ok($e,                                     "Created e");
is($e->value, '');
is($e->value('abc'), 'abc');
is($e->value, 'abc');

@s = $e->string;
cmp_ok(scalar @s, '==', 1);
is($s[0], "e*=iso-8859-1''abc"); 

is($e->value($m), $m);
is($e->value, $m);
@s = $e->string;
cmp_ok(scalar @s, '==', scalar @me);
is($s[0], "e*0*=iso-8859-1''$me[0]"); 
is($s[1], "e*1*=$me[1]"); 
is($s[2], "e*2*=$me[2]"); 
is($e->string, "; e*0*=iso-8859-1''$me[0]; e*1*=$me[1]; e*2*=$me[2]");

is($e->value('abc'), 'abc',                 "Reset contination");
is($e->value, 'abc');

@s = $e->string;
cmp_ok(scalar @s, '==', 1);
is($s[0], "e*=iso-8859-1''abc"); 

#
# Tests *NO* encoding with continuations
#

my $f = $mmfa->new('f', use_continuations => 1);
ok($f,                                     "Created f");
is($f->value, '');
is($f->value('abc'), 'abc');
is($f->value, 'abc');

is($f->value($m), $m);
is($f->value, $m);
@s = $f->string;
cmp_ok(scalar @s, '==', 2);
is($s[0], "f*0=\"$mq[0]\""); 
is($s[1], "f*1=\"$mq[1]\""); 
is($f->string, "; f*0=\"$mq[0]\"; f*1=\"$mq[1]\"");

is($f->value('abc'), 'abc',                 "Reset contination");
is($f->value, 'abc');

@s = $f->string;
cmp_ok(scalar @s, '==', 1);
is($s[0], 'f="abc"'); 

#
# Tests merging
#

my $g = $mmfa->new('g', use_continuations => 1);
ok($g,                                     "Created g");
my $h = $mmfa->new('h', use_continuations => 1);
ok($h,                                     "Created h");

$g->addComponent('g*1*=b');
is($g->value, '[continuation missing]b',   "Merge no continuation");
$h->addComponent('g*0*=a');
is($h->value, 'a');

ok($g->mergeComponent($h),                 "Merge with continuation");
is($g->value, 'ab');