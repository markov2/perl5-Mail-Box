#!/usr/local/bin/perl -w

#
# Test writing of mbox folders.
#

use strict;
use Test;
use File::Compare;
use File::Copy;
use File::Spec;

use lib '/home/markov/MailBox1/fake';
use Mail::Box::Mbox;

BEGIN {plan tests => 5}
#exit 0;

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mbox.cpy');
my $dest = File::Spec->catfile('t', 'mbox.cp2');

copy $orig, $src
    or die "Cannot create test folder: $!\n";

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'NEVER'
  , access       => 'rw'
  );

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
  , lazy_extract => 'NEVER'
  );

ok($copy);
ok($folder->messages==$copy->messages);

# Check also if the subjects are the same.

my @folder_subjects = sort map {$_->head->get('subject')||''} $folder->messages;
my @copy_subjects   = sort map {$_->head->get('subject')||''} $copy->messages;

while(@folder_subjects)
{   last unless shift(@folder_subjects) eq shift(@copy_subjects);
}
ok(!@folder_subjects);

#unlink $src;
