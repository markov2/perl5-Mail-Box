#!/usr/bin/perl
#
# Test the processing of resent groups.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

BEGIN {plan tests => 33}

use Mail::Message::Head::ResentGroup;
use Mail::Message::Head::Complete;
use Tools;
use IO::Scalar;

#
# Creation of a group
#

my $h = Mail::Message::Head::Complete->new;
ok(defined $h);

my $rg = Mail::Message::Head::ResentGroup->new
 ( head     => $h
 , From     => 'the.rg.group@example.com'
 , Received => 'obligatory field'
 );

ok(defined $rg);
isa_ok($rg, 'Mail::Message::Head::ResentGroup');

{ my $from = $rg->from;
  ok(ref $from);
  isa_ok($from, 'Mail::Message::Field');
  is($from->name, 'resent-from');
}

{  my $date = $rg->date;
   ok(ref $date);
   isa_ok($date, 'Mail::Message::Field');
   is($date->name, 'resent-date');
   is($date->Name, 'Resent-Date');
}

{  my $msgid = $rg->messageId;
   ok(ref $msgid);
   isa_ok($msgid, 'Mail::Message::Field');
   is($msgid->name, 'resent-message-id');
   is($msgid->Name, 'Resent-Message-ID');
   like($msgid, qr!^\<!);
   like($msgid, qr!\>$!);
}

#
# Interaction with a header
#


$h->add(From => 'me');
$h->add(To => 'you');
$h->addResentGroup($rg);

{  my $output;
   my $fh = IO::Scalar->new(\$output);
   $h->print($fh);
   $fh->close;

   # Cannot check the whole output: some lines are generated...
   $output =~ s/(Date|ID)\: .*/$1: [removed]/gm;

   is($output, <<'EXPECTED');
From: me
To: you
Received: obligatory field
Resent-Date: [removed]
Resent-From: the.rg.group@example.com
Resent-Message-ID: [removed]

EXPECTED

}

my $rg2 = $h->addResentGroup
 ( Received => 'now or never'
 , Cc            => 'cc to everyone'
 , Bcc           => 'undisclosed'
 , 'Return-Path' => 'Appears before everything else'
 , 'Message-ID'  => 'my own id'
 , Sender        => 'do not believe it'
 , From          => 'should be added'
 , To            => 'just to check every single field'
 );

ok(defined $rg2);
ok(ref $rg2);
isa_ok($rg2, 'Mail::Message::Head::ResentGroup');

{  my $output;
   my $fh = IO::Scalar->new(\$output);
   $h->print($fh);
   $fh->close;

   # Cannot check the whole output: some lines are generated...
   $output =~ s/Date\: .*/Date: [removed]/gm;
   $output =~ s/ID\: .*?\d.*/ID: [removed]/gm;

   is($output, <<'EXPECTED');
From: me
To: you
Return-Path: Appears before everything else
Received: now or never
Resent-Date: [removed]
Resent-From: should be added
Resent-Sender: do not believe it
Resent-To: just to check every single field
Resent-Cc: cc to everyone
Resent-Bcc: undisclosed
Resent-Message-ID: <my own id>
Received: obligatory field
Resent-Date: [removed]
Resent-From: the.rg.group@example.com
Resent-Message-ID: [removed]

EXPECTED
}

my $h2 = $h->clone;
ok(defined $h2);
isa_ok($h2, 'Mail::Message::Head::Complete');

{  my @rgs = $h2->resentGroups;
   cmp_ok(@rgs, '==', 2);
   ok(defined $rgs[0]);
   ok(ref $rgs[0]);
   ok($rgs[0]->isa('Mail::Message::Head::ResentGroup'));

   my $rg1 = $rgs[0];
   is($rg1->messageId, '<my own id>');

   my @of  = $rg1->orderedFields;
   cmp_ok(@of, '==', 9);

   @of     = $rgs[1]->orderedFields;
   cmp_ok(@of, '==', 4);

# Now delete, and close scope to avoid accidental reference to
# fields which should get cleaned-up.

   $rgs[0]->delete;
}

{  my @rgs = $h2->resentGroups;
   cmp_ok(@rgs, '==', 1);

   my @of  = $rgs[0]->orderedFields;
   cmp_ok(@of, '==', 4);

   my $output;
   my $fh = IO::Scalar->new(\$output);
   $h2->print($fh);
   $fh->close;

   # Cannot check the whole output: some lines are generated...
   $output =~ s/(Date|ID)\: .*/$1: [removed]/gm;

   is($output, <<'EXPECTED');
From: me
To: you
Received: obligatory field
Resent-Date: [removed]
Resent-From: the.rg.group@example.com
Resent-Message-ID: [removed]

EXPECTED

}
