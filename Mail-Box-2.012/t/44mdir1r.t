#!/usr/bin/perl

#
# Test reading of Maildir folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Maildir;
use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Copy;

# under development
BEGIN {plan tests => 0};
__END__

BEGIN {plan tests => 28}

my $mdsrc = File::Spec->catfile('t', 'maildir.src');

unpack_mbox2maildir($src, $mdsrc);

warn "   * Maildir under development\n";
ok(Mail::Box::Maildir->foundIn($mdsrc));

my $folder = new Mail::Box::Maildir
  ( folder       => $mdsrc
  , folderdir    => 't'
  , extract      => 'LAZY'
  , access       => 'r'
  , trace        => 'NONE'
  );

ok(defined $folder);

ok($folder->messages==45);
ok($folder->organization eq 'DIRECTORY');

#
# Count drafts (from Tools.pm flags)
#

my $drafts = 0;
$_->label('draft') && $drafts++ foreach $folder->messages;
ok($drafts==8);

#
# No single head should be read now, because extract == LAZY
# the default.
#

my $heads = 0;
foreach ($folder->messages)
{  $heads++ unless $_->head->isDelayed;
}
ok($heads==4);   # Last 4 messages started in new and have Status read

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
$folder = new Mail::Box::Maildir
  ( folder    => $mdsrc
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

$folder->message($_)->head->get('subject')
    foreach 5..13;

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

clean_dir $mdsrc;
