#!/usr/bin/perl

#
# Test access to folders using ties on hashes.
#

use Test;
use strict;
use warnings;

use lib qw(. t);
use Mail::Box::Mbox;
use Mail::Box::Tie::HASH;
use Mail::Message::Construct;
use Tools;

BEGIN {plan tests => 101}

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( folder    => $src
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'ALWAYS'
  , access    => 'rw'
  );

ok(defined $folder);

tie my(%folder), 'Mail::Box::Tie::HASH', $folder;
ok(keys %folder == 45);
ok(! defined $folder{not_existing});

my @keys = keys %folder;
foreach (@keys)
{   ok(defined $folder{$_});
    my $msg = $folder{$_};
    ok($folder{$_}->messageID eq $_);
}

my $msg   = $folder->message(4);
my $msgid = $msg->messageID;
ok($msg eq $folder{$msgid});

# delete $folder[2];    works for 5.6, but not for 5.5
ok(!$folder->message(4)->deleted);
ok(keys %folder == 45);
$folder{$msgid}->delete;
ok($folder->message(4)->deleted);
ok(keys %folder == 44);

# Double messages will not be added.
$folder{ (undef) } = $folder{$msgid}->clone;
ok(keys %folder == 44);

# Different message, however, will be added.
my $newmsg = Mail::Message->build(data => [ 'empty' ]);
$folder{undef} = $newmsg;
ok($folder->messages == 46);
ok(keys %folder == 45);

$folder->close(write => 'NEVER');
exit 0;
