#!/usr/bin/perl
#
# Test stripping CFWS  [comments and folding white spaces] as
# specified by rfc2822.
#

use Test;
use strict;
use warnings;

use lib qw(. t);

BEGIN {plan tests => 10}

use Mail::Message::Field;
use Mail::Address;
use Tools;

sub cfws($)
{   Mail::Message::Field->stripCFWS(shift);
}

ok(cfws('aap noot mies') eq 'aap noot mies');
ok(cfws("aap\nnoot\n") eq 'aap noot');
ok(cfws("aap (comment) noot") eq 'aap noot');
ok(cfws("(a) aap (comment) noot (c)") eq 'aap noot');
ok(cfws("aap (com (nested) ment) noot") eq 'aap noot');
ok(cfws("aap ((nested) comment) noot") eq 'aap noot');
ok(cfws("aap (comment (nested)) noot") eq 'aap noot');
ok(cfws("aap (comment(nested)) noot") eq 'aap noot');
ok(cfws("aap ((nested)comment(nested)) noot") eq 'aap noot');
ok(cfws("aap ((nes\n\nted)co\nmment(nested)\n) noot") eq 'aap noot');
