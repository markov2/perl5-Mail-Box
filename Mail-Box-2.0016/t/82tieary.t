#!/usr/bin/perl -w

#
# Test access to folders using ties.
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Mbox;
use Mail::Box::Tie::ARRAY;
use Mail::Message::Construct;
use Tools;

use Test;

BEGIN {plan tests => 9}


my $src  = File::Spec->catfile('t', 'mbox.src');

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder    => $src
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'ALWAYS'
  );

ok(defined $folder);
ok($folder->messages==45);

tie my(@folder), 'Mail::Box::Tie::ARRAY', $folder;
ok(@folder == 45);

ok($folder->message(4) eq $folder[4]);

# delete $folder[2];    works for 5.6, but not for 5.5
$folder[2]->delete;
ok($folder->message(2)->deleted);
ok(@folder == 45);

# Double messages will not be added.
push @folder, $folder[1]->clone;
ok(@folder == 45);

# Different message, however, will be added.
push @folder, Mail::Message->build(data => []);
ok($folder->messages == 46);
ok(@folder == 46);

exit 0;
