
use Test;
use File::Compare;
use lib '..';

BEGIN {plan tests => 7}

use Mail::Box::Mbox;

my $src  = 't/mbox.src';
my $dest = 't/mbox.cpy';

#exit 0;
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
