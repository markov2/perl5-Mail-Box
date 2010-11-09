#!/usr/bin/env perl
#
# Test processing of full fields with russian chars in utf-8.
#

use strict;
use warnings;

package Mail::Message::Field::Structured;   # define package name
package main;

use lib qw(. .. tests);
use Tools;

use utf8;
use Test::More;

BEGIN {
   if($] < 5.007003)
   {   plan skip_all => "Requires module Encode which requires Perl 5.7.3";
       exit 0;
   }

   eval 'require Mail::Message::Field::Structured';
   if($@)
   {   plan skip_all => 'Extended attributes not available (install Encode?)';
       exit 0;
   }
   else {   plan tests => 3; }
}

my $mmfs = 'Mail::Message::Field::Structured';

my $r = $mmfs->new('r', '');
isa_ok($r, $mmfs);

my $text_ru =
  "Раньше длинные multibyte-последовательности кодировались неправильно, теперь должно работать.";
is($r->decode($r->encode($text_ru, charset => 'utf-8', encoding => 'q')),
    $text_ru, 'encode/decode to/from QP');
is($r->decode($r->encode($text_ru, charset => 'utf-8', encoding => 'b')),
    $text_ru, 'encode/decode to/from Base64');
