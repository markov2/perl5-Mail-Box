#!/usr/bin/perl -w

#
# Test delay-loading on mbox folders.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Mbox;

use Test;
use File::Compare;
use File::Copy;
use File::Spec;

BEGIN {plan tests => 13}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mbox.cpy');

copy $orig, $src
    or die "Cannot create test folder: $!\n";

warn "hi1\n";
my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  );

warn "hi2\n";
die "Couldn't read $src: $!\n"
    unless $folder;

#
# None of the messages should be modified.
#

my $modified = 0;
$modified ||= $_->modified foreach $folder->messages;
ok(!$modified);

#
# Write unmodified folder to different file.
# Because file-to-file copy of unmodified messages, the result must be
# the same.
#

ok($folder->write);

# Try to read it back

my $copy = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  );

ok($copy);
ok($folder->messages==$copy->messages);

# Check also if the subjects are the same.

my @f_subjects = sort map {$_->head->get('subject') ||''} $folder->messages;
my @c_subjects   = sort map {$_->head->get('subject') ||''} $copy->messages;

while(@f_subjects)
{   last unless shift(@f_subjects) eq shift(@c_subjects);
}
ok(!@f_subjects);

#
# None of the messages should be parsed yet.
#

my $parsed = 0;
$parsed ||= $_->isParsed foreach $folder->messages;
ok(!$parsed);

#
# Force one message to be loaded.
#

my $message = $folder->message(3);
ok(ref $message);
my $body = $message->body;
ok($message->isParsed);

ok($message->isa('Mail::Message'));

#
# Ask for a new field from the header, which is not taken by
# default.  The message should get parsed.
#

ok(!defined $message->head->get('xyz'));

ok(not $folder->message(2)->isParsed);
ok(defined $folder->message(2)->head->get('x-mailer'));
ok($folder->message(2)->isParsed);

unlink $src;
