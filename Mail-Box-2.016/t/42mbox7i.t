#!/usr/bin/perl

#
# Test writing of mbox folders using the inplace policy.
#

use Test;
use strict;
use warnings;

use lib qw(. t);
use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Copy;

BEGIN {plan tests => 99}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

copy $src, $cpy
    or die "Cannot create test folder $cpy: $!\n";

my $folder = new Mail::Box::Mbox
  ( folder       => "=$cpyfn"
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , log          => 'NOTICES'
#, trace => 'NOTICES'
  );

die "Couldn't read $cpy: $!\n"
     unless $folder;

#
# None of the messages should be modified.
#

my $modified = 0;
$modified ||= $_->modified foreach $folder->messages;
ok(!$modified);

#
# Write unmodified folder.  This should be ready immediately.
#

ok($folder->write(policy => 'INPLACE'));
my @progress = $folder->report('PROGRESS');
ok(grep m/not changed/, @progress);

#
# All messages must still be delayed.
#

my $msgnr = 0;
foreach ($folder->messages)
{   if($_->isDelayed)  {ok(1)}
    else { warn "Warn: failed message $msgnr.\n"; ok(0) }
    $msgnr++;
}

#
# Now modify the folder, and write it again.
#

my $modmsgnr = 30;
$folder->message($modmsgnr)->modified(1);
ok($folder->write(policy => 'INPLACE'));

#
# All before messages before $modmsgnr must still be delayed.
#

$msgnr = 0;
foreach ($folder->messages)
{   my $right = $_->isDelayed ? ($msgnr < $modmsgnr) : ($msgnr >= $modmsgnr);
    warn "Warn: failed message $msgnr.\n" unless $right;
    ok($right);
    $msgnr++;
}

# Check also if the subjects are the same.
# Try to read it back

my $copy = new Mail::Box::Mbox
  ( folder    => '=mbox.cpy'
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'ALWAYS'
  );

ok($copy);
ok($folder->messages==$copy->messages);

# Check also if the subjects are the same.

my @folder_subjects = sort map {$_->get('subject')||''} $folder->messages;
my @copy_subjects   = sort map {$_->get('subject')||''} $copy->messages;

while(@folder_subjects)
{   last unless shift(@folder_subjects) eq shift(@copy_subjects);
}
ok(!@folder_subjects);

#
# Now the same check, but using delete... removing two messages.
#

$folder->message(5)->delete;
ok(1);
$folder->message(35)->delete;
ok(1);

### work to be done
unlink $cpy;
