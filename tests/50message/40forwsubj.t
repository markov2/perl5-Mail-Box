#!/usr/bin/perl
#
# Test the creation of forward subjects
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Message::Construct::Forward;

BEGIN {plan tests => 7}

is(Mail::Message->forwardSubject('subject'), 'Forw: subject');
is(Mail::Message->forwardSubject('Re: subject'), 'Forw: Re: subject');
is(Mail::Message->forwardSubject('Re[2]: subject'), 'Forw: Re[2]: subject');
is(Mail::Message->forwardSubject('subject (forw)'), 'Forw: subject (forw)');
is(Mail::Message->forwardSubject('subject (Re)'), 'Forw: subject (Re)');
is(Mail::Message->forwardSubject(undef), 'Forwarded');
is(Mail::Message->forwardSubject(''), 'Forwarded');
