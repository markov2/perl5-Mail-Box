#!/usr/bin/perl

#
# Test delay-loading on mbox folders.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);
use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Copy;

BEGIN {plan tests => 288}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

copy $src, $cpy
    or die "Cannot create test folder: $!\n";

my $folder = new Mail::Box::Mbox
  ( folder       => "=$cpyfn"
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  );

die "Couldn't read $cpy: $!\n"
    unless $folder;

#
# Check that the whole folder is continuous
#

my ($end, $msgnr) = (0, 0);
foreach my $message ($folder->messages)
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

if($^O =~ /win32/i)   # Correct count for empty trailing line
     { cmp_ok($end+2 , "==",  -s $folder->filename); }
else { cmp_ok($end+1 , "==",  -s $folder->filename); }

#
# None of the messages should be modified.
#

my $modified = 0;
$modified ||= $_->modified foreach $folder->messages;
ok(! $modified);

#
# Write unmodified folder to different file.
# Because file-to-file copy of unmodified messages, the result must be
# the same.
#

my $oldsize = -s $folder->filename;

$folder->modified(1);    # force write
ok($folder->write);
cmp_ok($oldsize-1 , "==",  -s $folder->filename);

# Try to read it back

my $copy = new Mail::Box::Mbox
  ( folder       => "=$cpyfn"
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  );

ok(defined $copy);
cmp_ok($folder->messages, "==", $copy->messages);

# Check also if the subjects are the same.

my @f_subjects = map {$_->head->get('subject') ||''} $folder->messages;
my @c_subjects = map {$_->head->get('subject') ||''} $copy->messages;

while(@f_subjects)
{   my $f = shift @f_subjects;
    my $c = shift @c_subjects;
    last unless $f eq $c;
}
ok(!@f_subjects);

#
# None of the messages should be parsed yet.
#

my $parsed = 0;
$_->isParsed && $parsed++ foreach $folder->messages;
cmp_ok($parsed, "==", 0);

#
# Check that the whole folder is continuous
#

($end, $msgnr) = (0, 0);
foreach my $message ($copy->messages)
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
cmp_ok($end, "==",  -s $copy->filename);

#
# None of the messages should be parsed still.
#

$parsed = 0;
$_->isParsed && $parsed++ foreach $copy->messages;
cmp_ok($parsed, "==", 0);

#
# Force one message to be loaded.
#

my $message = $copy->message(3)->forceLoad;
ok(ref $message);
my $body = $message->body;
ok($message->isParsed);

isa_ok($message, 'Mail::Message');

#
# Ask for a new field from the header, which is not taken by
# default.  The message should get parsed.
#

ok(!defined $message->head->get('xyz'));

ok(not $copy->message(2)->isParsed);
ok(defined $copy->message(2)->head->get('x-mailer'));
isa_ok($copy->message(2)->head, 'Mail::Message::Head::Complete');
ok(not $copy->message(2)->isParsed);

#unlink $cpy;
