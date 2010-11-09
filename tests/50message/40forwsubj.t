#!/usr/bin/env perl
#
# Test the creation of forward subjects
#

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More tests => 7;

use Mail::Message::Construct::Forward;

is(Mail::Message->forwardSubject('subject'), 'Forw: subject');
is(Mail::Message->forwardSubject('Re: subject'), 'Forw: Re: subject');
is(Mail::Message->forwardSubject('Re[2]: subject'), 'Forw: Re[2]: subject');
is(Mail::Message->forwardSubject('subject (forw)'), 'Forw: subject (forw)');
is(Mail::Message->forwardSubject('subject (Re)'), 'Forw: subject (Re)');
is(Mail::Message->forwardSubject(undef), 'Forwarded');
is(Mail::Message->forwardSubject(''), 'Forwarded');
