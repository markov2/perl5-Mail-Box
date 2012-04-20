#!/usr/bin/env perl
#
# Test processing of general parsing of fields
#

use strict;
use warnings;

package Mail::Message::Field::Full;   # define package name
package main;

use lib qw(. .. tests);
use Tools;

use Test::More;

BEGIN {
   if($] < 5.007003)
   {   plan skip_all => "Requires module Encode which requires Perl 5.7.3";
       exit 0;
   }

   eval 'require Mail::Message::Field::Full';
   if($@)
   {
warn $@;
       plan skip_all => 'Extended attributes not available (install Encode?)';
       exit 0;
   }
   else
   {   plan tests => 38;
   }
}


my $mmff = 'Mail::Message::Field::Full';

#
# Test consuming phrases
#

my @tests =
 ( 'hi! this is me <tux>' => ['hi! this is me', '<tux>' ]
 , ' aap, noot <tux>'     => ['aap', ', noot <tux>' ]
 , '" aap, noot " <tux>'  => [' aap, noot ', ' <tux>' ]
 , '"aap", "noot"'        => ['aap', ', "noot"' ]
 , '"a\\"b\\"c" d'        => ['a"b"c', ' d' ]
 , '"\\"b\\"" d'          => ['"b"', ' d' ]
 , '"a\\)b\\(c" d'        => ['a\\)b\\(c', ' d' ]
 , '<tux>'                => [ undef, '<tux>' ]
 , ' <tux>'               => [ undef, '<tux>' ]
 , '" " <tux>'            => [ ' ', ' <tux>' ]
 );

while(@tests)
{   my ($from, $to) = (shift @tests, shift @tests);
    my ($exp_phrase, $exp_rest) = @$to;

    my ($phrase, $rest) = $mmff->consumePhrase($from);
    is($phrase, $exp_phrase,  $from);
    is($rest, $exp_rest,      $from);
}

#
# Test consuming comments
#

@tests =
 ( '(this is a comment) <tux>' => [ 'this is a comment', ' <tux>' ]
 , '(this)'                    => [ 'this', '' ]
 , 'this'                      => [ undef, 'this' ]
 , ' (a(b)c) <tux>'            => [ 'a(b)c', ' <tux>' ]
 , '((a)b(c)) <tux>'           => [ '(a)b(c)', ' <tux>' ]
 , '((a)b(c) <tux>'            => [ undef, '((a)b(c) <tux>' ]
 , '(a\(b) <tux>'              => [ 'a(b', ' <tux>' ]
 , '(a <tux>'                  => [ undef, '(a <tux>' ]
 , 'a) <tux>'                  => [ undef, 'a) <tux>' ]
 );

while(@tests)
{   my ($from, $to) = (shift @tests, shift @tests);
    my ($exp_comment, $exp_rest) = @$to;

    my ($comment, $rest) = $mmff->consumeComment($from);
    is($comment, $exp_comment,  $from);
    is($rest, $exp_rest,      $from);
}

#
