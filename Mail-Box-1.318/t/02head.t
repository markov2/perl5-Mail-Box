#!/usr/bin/perl -w
#
# Test the processing of a whole message header, not the reading of a
# header from file.
#

use Test;
use strict;
use lib '/home/markov/fake';

BEGIN {plan tests => 20}

use Mail::Message::Head;
use IO::Scalar;

my $h = Mail::Message::Head->new;
my @o = $h->names;
ok(@o==0);

# Adding a first.

$h->add(From => 'me@home');
@o = $h->names;
ok(@o==1);

my @f = $h->get('From'); # list context
ok(@f==1);
ok($f[0]->body eq 'me@home');

my $f = $h->get('From'); # scalar context
ok($f->body eq 'me@home');

# Adding a second.

$h->add(From => 'you2me');
@o = $h->names;
ok(@o==1);

@f = $h->get('From'); # list context
ok(@f==2);
ok($f[0]->body eq 'me@home');
ok($f[1]->body eq 'you2me');

$f = $h->get('From'); # scalar context
ok($f->body eq 'you2me');

# Missing

@f = $h->get('unknown');
ok(@f==0);

$f = $h->get('unknown');
ok(! defined $f);

# Set

$h->set(From => 'perl');
@f = $h->get('From');
ok(@f==1);

@o = $h->names;
ok(@o==1);

$h->set(New => 'test');
@o = $h->names;
ok(@o==2);
ok($o[0] eq 'from');
ok($o[1] eq 'new');

# Reset

$h->reset('From');
@f = $h->get('From');
ok(@f==0);

my $l = Mail::Message::Field->new(New => 'other');
$h->reset('NEW', $h->get('new'), $l);
@f = $h->get('neW');
ok(@f==2);

# Print

$h->add(Subject => 'hallo!');
$h->add(To => 'the world');
$h->add(From => 'me');   # must appear first because memory.

my $output;
my $fakefile = new IO::Scalar \$output;

$h->print($fakefile);
ok($output eq <<'EXPECTED_OUTPUT');
From: me
New: test
New: other
Subject: hallo!
To: the world
EXPECTED_OUTPUT

$fakefile->close;
