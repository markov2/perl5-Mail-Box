#!/usr/bin/perl

#
# Test reading of MH folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::MH;
use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Copy;

BEGIN {plan tests => 27}

my $mhsrc = File::Spec->catfile('t', 'mh.src');

unpack_mbox2mh($src, $mhsrc);

warn "   * MH status: released\n";
ok(Mail::Box::MH->foundIn($mhsrc));

my $folder = new Mail::Box::MH
  ( folder       => $mhsrc
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  );

ok(defined $folder);

# We skipped message number 13 in the production, but that shouldn't
# distrub things.

ok($folder->messages==45);
ok($folder->organization eq 'DIRECTORY');

#
# No single head should be read now, because extract == LAZY
# the default.
#

my $heads = 0;
foreach ($folder->messages)
{  $heads++ unless $_->head->isDelayed;
}
ok($heads==0);

#
# Loading a header should not be done unless really necessary.
#

my $message = $folder->message(7);
ok($message->head->isDelayed);

ok($message->filename);   # already known, but should not trigger header
ok($message->head->isDelayed);

#
# Nothing should be parsed yet
#

my $parsed = 0;
foreach ($folder->messages)
{  $parsed++ if $_->isParsed;
}
ok($parsed==0);

#
# Trigger one message to get read.
#

ok($message->body->string);       # trigger body loading.
ok($message->isParsed);

#
# Test taking header
#

$message = $folder->message(8);
ok(defined $message->head->get('subject'));
ok(not $message->isParsed);
ok(ref $message->head eq 'Mail::Message::Head::Complete');

# This shouldn't cause any parsings: we do lazy extract, but Mail::Box
# will always take the `Subject' header for us.

my @subjects = map { chomp; $_ }
                  map {$_->head->get('subject') || '<undef>' }
                     $folder->messages;

$parsed = 0;
$heads  = 0;
foreach ($folder->messages)
{  $parsed++ unless $_->isDelayed;
   $heads++  unless $_->head->isDelayed;
}
ok($parsed==1);  # message 7
ok($heads==45);

#
# The subjects must be the same as from the original Mail::Box::Mbox
# There are some differences with new-lines at the end of headerlines
#

my $mbox = Mail::Box::Mbox->new
  ( folder      => $src
  , folderdir   => 't'
  , lock_type   => 'NONE'
  , access      => 'r'
  );

my @fsubjects = map { chomp; $_ }
                   map {$_->head->get('subject') || '<undef>'}
                      $mbox->messages;

my (%subjects);
$subjects{$_}++ foreach @subjects;
$subjects{$_}-- foreach @fsubjects;

my $missed = 0;
foreach (keys %subjects)
{   $missed++ if $subjects{$_};
    warn "Still left: $_ ($subjects{$_}x)\n" if $subjects{$_};
}
ok(!$missed);

#
# Check if we can read a body.
#

my $msg3 = $folder->message(3);
my $body = $msg3->body;
ok(defined $body);
ok(@$body==42);       # check expected number of lines in message 4.

$folder->close;

#
# Now with partially lazy extract.
#

my $parse_size = 5000;
$folder = new Mail::Box::MH
  ( folder    => $mhsrc
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => $parse_size  # messages > $parse_size bytes stay unloaded.
  , access    => 'rw'
  );

ok(defined $folder);

ok($folder->messages==45);

$parsed     = 0;
$heads      = 0;
my $mistake = 0;
foreach ($folder->messages)
{   $parsed++  unless $_->isDelayed;
    $heads++   unless $_->head->isDelayed;
    $mistake++ if !$_->isDelayed && $_->size > $parse_size;
}

ok(not $mistake);
ok(not $parsed);
ok(not $heads);

foreach (5..13)
{   $folder->message($_)->head->get('subject');
}

$parsed  = 0;
$heads   = 0;
$mistake = 0;
foreach ($folder->messages)
{   $parsed++  unless $_->isDelayed;
    $heads++   unless $_->head->isDelayed;
    $mistake++ if !$_->isDelayed && $_->body->size > $parse_size;
}

ok(not $mistake);
ok($parsed == 7);
ok($heads == 9);

# No clean-dir: see how it behaves when the folder is not explictly
# closed before the program terminates.  Terrible things can happen
# during auto-cleanup
#clean_dir $mhsrc;
