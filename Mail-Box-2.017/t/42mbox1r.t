#!/usr/bin/perl
#
# Test reading of mbox folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Mail::Box::Mbox;
use Tools;

use File::Compare;

BEGIN {plan tests => 59}

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
ok($folder->messages == 45);
ok($folder->organization eq 'FILE');

#
# Extract one message.
#

my $message = $folder->message(2);
ok(defined $message);
ok($message->isa('Mail::Box::Message'));

#
# Extract a few messages.
#

my @some = $folder->messages(3,7);
ok(@some==5);
ok($some[0]->isa('Mail::Box::Message'));

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
{   $msgnr++;
    my $ok = 0;
    my ($msgbegin, $msgend)   = $message->fileLocation;
    my ($headbegin, $headend) = $message->head->fileLocation;
    my ($bodybegin, $bodyend) = $message->body->fileLocation;

#warn "($msgbegin, $msgend) ($headbegin, $headend) ($bodybegin, $bodyend)\n";
    $ok++ if $msgbegin==$end;
    $ok++ if $headbegin > $msgbegin;
    $ok++ if $bodybegin==$headend;
    $end = $bodyend;
    ok($ok==3);
    warn "Message ", $message->get('subject') || '<no subject>', " failed\n"
       unless $ok==3;
}
ok($end== -s $folder->filename);

#
# Try to delete a message
#

$folder->message(2)->delete;
ok($folder->message(2)->deleted);
ok($folder->messages == 45);

ok($folder->messages('ACTIVE')  == 44);
ok($folder->messages('DELETED') ==  1);

$folder->close(write => 'NEVER');

exit 0;
