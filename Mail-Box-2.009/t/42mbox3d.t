#!/usr/bin/perl

#
# Test delay-loading on mbox folders.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Mbox;
use Tools;

use File::Compare;
use File::Copy;

BEGIN {plan tests => 108}

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
ok($oldsize == -s $folder->filename);

# Try to read it back

my $copy = new Mail::Box::Mbox
  ( folder       => "=$cpyfn"
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  );

ok(defined $copy);
ok($folder->messages==$copy->messages);

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
$parsed ||= $_->isParsed foreach $folder->messages;
ok(!$parsed);


#
# Check that the whole folder is continuous
#

($end, $msgnr) = (0, 0);
foreach my $message ($copy->messages)
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
ok($end== -s $copy->filename);

#
# None of the messages should be parsed still.
#

$parsed = 0;
$parsed ||= $_->isParsed foreach $copy->messages;
ok(!$parsed);

#
# Force one message to be loaded.
#

my $message = $folder->message(3)->forceLoad;
ok(ref $message);
my $body = $message->body;
ok($message->isParsed);

ok($message->isa('Mail::Message'));

#
# Ask for a new field from the header, which is not taken by
# default.  The message should get parsed.
#

ok(!defined $message->head->get('xyz'));

ok(not $folder->message(2)->isParsed);
ok(defined $folder->message(2)->head->get('x-mailer'));
ok($folder->message(2)->head->isa('Mail::Message::Head::Complete'));
ok(not $folder->message(2)->isParsed);

#unlink $cpy;
