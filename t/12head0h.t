#!/usr/bin/perl
#
# Test the processing of a whole message header, not the reading of a
# header from file.
#

use Test;
use strict;
use warnings;

use lib qw(. t);

BEGIN {plan tests => 25}

use Mail::Message::Head::Complete;
use Tools;
use IO::Scalar;

my $h = Mail::Message::Head::Complete->new;
{  my @o = $h->names;
   ok(@o==0);
}

# Adding a first.

{  my $a = $h->add(From => 'me@home');
   ok(ref $a);
   ok($a->isa('Mail::Message::Field'));
}

{  my @o = $h->names;
   ok(@o==1);
}

{  my @f = $h->get('From'); # list context
   ok(@f==1);
   ok(ref $f[0]);
   ok($f[0]->isa('Mail::Message::Field'));
   ok($f[0]->body eq 'me@home');
}

{  my $f = $h->get('From'); # scalar context
   ok($f->body eq 'me@home');
}

# Adding a second.

$h->add(From => 'you2me');
{  my @o = $h->names;
   ok(@o==1);
}

{  my @f = $h->get('From'); # list context
   ok(@f==2);
   ok($f[0]->body eq 'me@home');
   ok($f[1]->body eq 'you2me');
}

{  my $f = $h->get('From'); # scalar context
   ok($f->body eq 'you2me');
}

# Missing

{  my @f = $h->get('unknown');
   ok(@f==0);
}

{  my $f = $h->get('unknown');
   ok(! defined $f);
}

# Set

{
   $h->set(From => 'perl');
   my @f = $h->get('From');
   ok(@f==1);
}

{  my @o = $h->names;
   ok(@o==1);
}

$h->set(New => 'test');
{  my @o = sort $h->names;
   ok(@o==2);
   ok($o[0] eq 'from');
   ok($o[1] eq 'new');
}

# Reset

$h->reset('From');
{  my @f = $h->get('From');
   ok(@f==0);
}

{
   my $l = Mail::Message::Field->new(New => 'other');
   $h->reset('NEW', $h->get('new'), $l);
}

{  my @f = $h->get('neW');
   ok(@f==2);
}

# Print

$h->add(Subject => 'hallo!');
$h->add(To => 'the world');
$h->add(From => 'me');

my $output;
my $fakefile = new IO::Scalar \$output;

$h->print($fakefile, 0);
my $expected = <<'EXPECTED_OUTPUT';
New: test
New: other
Subject: hallo!
To: the world
From: me

EXPECTED_OUTPUT

ok($output eq $expected);
ok($h->toString eq $expected);

$fakefile->close;
