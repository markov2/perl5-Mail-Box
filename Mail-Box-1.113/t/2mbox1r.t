#!/usr/local/bin/perl -w
#
# Test reading of mbox folders.
#

use Test;
use File::Compare;
use strict;
use lib '..';
use File::Spec;

BEGIN {plan tests => 8}

use Mail::Box::Mbox;

my $src  = File::Spec->catfile('t', 'mbox.src');
my $dest = File::Spec->catfile('t', 'mbox.cpy');

warn "   * Mbox status BETA\n";
ok(Mail::Box::Mbox->foundIn($src));

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'NEVER'
  );

ok(defined $folder);
ok($folder->messages == 45);

#
# Extract one message.
#

my $message = $folder->message(2);
ok(defined $message);
ok($message->isa('Mail::Box::Message'));

#
# All message should be parsed.
#

my $parsed = 1;
$parsed &&= $_->isParsed foreach $folder->messages;
ok($parsed);

#
# Try to delete a message
#

$folder->message(2)->delete;
ok($folder->messages == 44);
ok($folder->allMessages == 45);

exit 0;
