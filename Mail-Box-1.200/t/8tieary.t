#!/usr/local/bin/perl -w

#
# Test access to folders using ties.
#

use strict;
use Test;

BEGIN {plan tests => 8}

use lib '..', 't';
use Mail::Box::Mbox;
use Mail::Box::Tie;

my $src  = File::Spec->catfile('t', 'mbox.src');

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'NEVER'
  );

ok(defined $folder);
ok($folder->allMessages==45);

tie my(@folder), 'Mail::Box::Tie', $folder;
ok(@folder == 45);

ok($folder->message(4) eq $folder[4]);

# delete $folder[2];    works for 5.6, but not for 5.5
$folder[2]->delete;
ok($folder->message(2)->deleted);
ok(@folder == 45);

# Double messages will not be added.
push @folder, $folder[1];
ok(@folder == 45);

# Different message, however, will be added.
push @folder, MIME::Entity->build(Data => []);
ok($folder->allMessages == 46);

exit 0;
