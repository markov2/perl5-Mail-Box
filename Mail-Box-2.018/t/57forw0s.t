#!/usr/bin/perl
#
# Test the creation of forward subjects
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Message::Construct;

BEGIN {plan tests => 7}

ok(Mail::Message->forwardSubject('subject') eq 'Forw: subject');
ok(Mail::Message->forwardSubject('Re: subject') eq 'Forw: Re: subject');
ok(Mail::Message->forwardSubject('Re[2]: subject') eq 'Forw: Re[2]: subject');
ok(Mail::Message->forwardSubject('subject (forw)') eq 'Forw: subject (forw)');
ok(Mail::Message->forwardSubject('subject (Re)') eq 'Forw: subject (Re)');
ok(Mail::Message->forwardSubject(undef) eq 'Forwarded');
ok(Mail::Message->forwardSubject('') eq 'Forwarded');
