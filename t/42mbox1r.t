#!/usr/bin/perl
#
# Test reading of mbox folders.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

use Mail::Box::Mbox;
use Tools;

use File::Compare;

BEGIN {plan tests => 149}

my @src = (folder => "=$fn", folderdir => 't');

warn "   * Mbox status: released\n";
ok(Mail::Box::Mbox->foundIn(@src));

#
# The folder is read.
#

my $folder = new Mail::Box::Mbox
  ( @src
  , lock_type    => 'NONE'
  , extract      => 'ALWAYS'
  );

ok(defined $folder);
cmp_ok($folder->messages , "==",  45);
is($folder->organization, 'FILE');

#
# Extract one message.
#

my $message = $folder->message(2);
ok(defined $message);
isa_ok($message, 'Mail::Box::Message');

#
# Extract a few messages.
#

my @some = $folder->messages(3,7);
cmp_ok(@some, "==", 5);
isa_ok($some[0], 'Mail::Box::Message');

#
# All message should be parsed.
#

my $parsed = 1;
$parsed &&= $_->isParsed foreach $folder->messages;
ok($parsed);

#
# Check whether all message's locations are nicely connected.
#

my ($end, $msgnr) = (0, 0);
foreach $message ($folder->messages)
{   my ($msgbegin, $msgend)   = $message->fileLocation;
    my ($headbegin, $headend) = $message->head->fileLocation;
    my ($bodybegin, $bodyend) = $message->body->fileLocation;

#warn "($msgbegin, $msgend) ($headbegin, $headend) ($bodybegin, $bodyend)\n";
    cmp_ok($msgbegin, "==", $end,      "begin $msgnr");
    cmp_ok($headbegin, ">", $msgbegin, "end $msgnr");
    cmp_ok($bodybegin, "==", $headend, "glue $msgnr");
    $end = $bodyend;

    $msgnr++;
}
cmp_ok($end, "==",  -s $folder->filename);

#
# Try to delete a message
#

$folder->message(2)->delete;
ok($folder->message(2)->deleted);
cmp_ok($folder->messages , "==",  45);

cmp_ok($folder->messages('ACTIVE')  , "==",  44);
cmp_ok($folder->messages('DELETED') , "==",   1);

$folder->close(write => 'NEVER');

exit 0;
