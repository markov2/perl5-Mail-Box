
#
# Test appending messages on Mbox folders.
#

use Test;
use File::Compare;
use File::Copy;
use lib '..';
use strict;

use Mail::Box::Manager;

BEGIN {plan tests => 6}
#exit 0;

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = 't/mbox.src';
my $src  = 't/mbox.cpy';

copy $orig, $src or die "Cannot create test folder.";

my $mgr = Mail::Box::Manager->new;

my $folder = $mgr->open
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  , save_on_exit => 0
  );

die "Couldn't read $src." unless $folder;

ok($folder->messages==45);

# Add a message which is already in the opened folder.  This should
# be ignored.

$folder->addMessage($folder->message(3));
ok($folder->messages==45);

#
# Create an MIME::Entity and add this to the open folder.
#

my $msg = MIME::Entity->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , Data    => [ "a short message\n", "of two lines.\n" ]
  );

$mgr->appendMessage($src, $msg);
ok($folder->messages==46);

ok($mgr->openFolders==1);
$mgr->close($folder);
ok($mgr->openFolders==0);

my $old_size = -s $src;
$mgr->appendMessage($src, $msg
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  );

ok($old_size != -s $src);
