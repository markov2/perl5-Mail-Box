#!/usr/bin/perl
#
# Test the processing of resent groups.
#

use Test;
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
ok($rg->isa('Mail::Message::Head::ResentGroup'));

{ my $from = $rg->from;
  ok(ref $from);
  ok($from->isa('Mail::Message::Field'));
  ok($from->name eq 'resent-from');
}

{  my $date = $rg->date;
   ok(ref $date);
   ok($date->isa('Mail::Message::Field'));
   ok($date->name eq 'resent-date');
   ok($date->Name eq 'Resent-Date');
}

{  my $msgid = $rg->messageId;
   ok(ref $msgid);
   ok($msgid->isa('Mail::Message::Field'));
   ok($msgid->name eq 'resent-message-id');
   ok($msgid->Name eq 'Resent-Message-ID');
   ok($msgid =~ m!^\<!);
   ok($msgid =~ m!\>$!);
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

   ok($output eq <<'EXPECTED');
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
ok($rg2->isa('Mail::Message::Head::ResentGroup'));

{  my $output;
   my $fh = IO::Scalar->new(\$output);
   $h->print($fh);
   $fh->close;

   # Cannot check the whole output: some lines are generated...
   $output =~ s/Date\: .*/Date: [removed]/gm;
   $output =~ s/ID\: .*?\d.*/ID: [removed]/gm;

   ok($output eq <<'EXPECTED');
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
ok($h2->isa('Mail::Message::Head::Complete'));

{  my @rgs = $h2->resentGroups;
   ok(@rgs==2);
   ok(defined $rgs[0]);
   ok(ref $rgs[0]);
   ok($rgs[0]->isa('Mail::Message::Head::ResentGroup'));

   my $rg1 = $rgs[0];
   ok($rg1->messageId eq '<my own id>');

   my @of  = $rg1->orderedFields;
   ok(@of==9);

   @of     = $rgs[1]->orderedFields;
   ok(@of==4);

# Now delete, and close scope to avoid accidental reference to
# fields which should get cleaned-up.

   $rgs[0]->delete;
}

{  my @rgs = $h2->resentGroups;
   ok(@rgs==1);

   my @of  = $rgs[0]->orderedFields;
   ok(@of==4);

   my $output;
   my $fh = IO::Scalar->new(\$output);
   $h2->print($fh);
   $fh->close;

   # Cannot check the whole output: some lines are generated...
   $output =~ s/(Date|ID)\: .*/$1: [removed]/gm;

   ok($output eq <<'EXPECTED');
From: me
To: you
Received: obligatory field
Resent-Date: [removed]
Resent-From: the.rg.group@example.com
Resent-Message-ID: [removed]

EXPECTED

}
