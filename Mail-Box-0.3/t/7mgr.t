
#
# Test the folder manager with automatic folder-type detection.
#

use Test;
use lib '..';

BEGIN {plan tests => 5}

use Mail::Box::Manager;

my $src  = 't/mbox.src';

my $manager = Mail::Box::Manager->new;

my $folder  = $manager->open
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  );

ok(defined $folder);
ok($folder->isa('Mail::Box::Mbox'));

my $second = $manager->open
  ( folder       => $src
  , lock_method  => 'NONE'
  );

ok(defined $second);
ok($folder eq $second);
ok($manager->openFolders==1);

exit 0;
