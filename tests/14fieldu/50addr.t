#!/usr/bin/perl
#
# Test processing of addresses
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

package Mail::Message::Field::Addresses;   # define package name
package main;

BEGIN {
   if($] < 5.007003)
   {   plan skip_all => "Requires module Encode which requires Perl 5.7.3";
       exit 0;
   }

   eval 'require Mail::Message::Field::Addresses';
   if($@)
   {
warn $@;
       plan skip_all => 'Extended attributes not available (install Encode?)';
       exit 0;
   }
   else
   {   plan tests => 4;
   }
}

use Tools;

my $mmfa  = 'Mail::Message::Field::Address';
my $mmfag = 'Mail::Message::Field::AddrGroup';
my $mmfas = 'Mail::Message::Field::Addresses';

#
# Test single addresses
#

my $b = $mmfa->new(name => 'Mark Overmeer', local => 'markov',
   domain => 'cpan.org', comment => 'This is me!');
ok(defined $b,                                     'Created b');
isa_ok($b, $mmfa);
is($b->name, 'Mark Overmeer');
is($b->address, 'markov@cpan.org');

exit(0);    # till here it works....

is($b->string, 'Mark Overmeer <markov@cpan.org> (This is me!)');

#
# Test whole field (Addresses)
#

my $a = $mmfas->new('Cc');
ok(defined $a,                                     'Create a');
isa_ok($a, $mmfa);

my $jd = 'John Doe <jdoe@machine.example>';
ok($a->parse($jd));
my @g = $a->groups;
cmp_ok(scalar @g, '==', 1);
my $g0 = $g[0];
ok(defined $g0);

is($g0->name, '');
my @ga = $g0->addresses;
cmp_ok(scalar @ga, '==', 1);
is($g0->string, $jd); 

my @a = $a->addresses;
cmp_ok(scalar @a, '==', 1);
my $a0 = $a[0];
ok(defined $a0);

is($a0->name, 'John Doe');
is($a0->address, 'jdoe@machine.example');
is($a0->local, 'jdoe');
is($a0->domain, 'machine.example');

is($a->string, $jd);

__END__
"Joe Q. Public" <john.q.public@example.com>
 Mary Smith <mary@x.test>, jdoe@example.org, Who? <one@y.test>
<boss@nil.test>, "Giant; \"Big\" Box" <sysservices@example.net>
 A Group:Chris Jones <c@a.test>,joe@where.test,John <jdoe@one.test>;
 Undisclosed recipients:;
"Mary Smith: Personal Account" <smith@home.example>
Jane Brown <j-brown@other.example>
From: Pete(A wonderful \) chap) <pete(his account)@silly.test(his host)>
From: Pete(A wonderful \) chap) <pete(his account)@silly.test(his host)>
To:A Group(Some people)
     :Chris Jones <c@(Chris's host.)public.example>,
         joe@example.org,
  John <jdoe@one.test> (my dear friend); (the end of the group)
Cc:(Empty list)(start)Undisclosed recipients  :(nobody(that I know))  ;
From  : John Doe <jdoe@machine(comment).  example>
Mary Smith <@machine.tld:mary@example.net>, , jdoe@test   . example
