#!/usr/bin/perl
#
# Test reading of dbx folders.
#

use Test::More;
use strict;
use warnings;

use lib qw(. .. tests);

use Tools;

use File::Compare;

BEGIN
{
   eval { require Mail::Box::Dbx };

   if($@ || ! Mail::Box::Dbx->type eq 'dbx')
   {   plan(skip_all => 'Mail::Box::Dbx is not installed');
       exit 0;
   }
   elsif(not (-d '45dbx/testfolders' || -d 'tests/45dbx/testfolders'))
   {   plan(skip_all => 'dbx test folders are not distributed');
       exit 0;
   }

   plan tests => 19;
}

my @src = (folderdir => '45dbx/testfolders');

ok(Mail::Box::Dbx->foundIn('Folder.dbx'), 'check foundIn');
ok(!Mail::Box::Dbx->foundIn('Folder.mbox'), 'check foundIn');

#
# The folder is read.
#

my $folder = Mail::Box::Dbx->new
  ( @src
  , lock_type    => 'NONE'
  , extract      => 'ALWAYS'
  );

ok(defined $folder,                  'check success open folder');
exit 1 unless defined $folder;

ok(! $folder->isModified);
is($folder->organization, 'FILE',    'folder organization FILE');
cmp_ok($folder->messages , "==",  0, 'found no messages');

my @subf = $folder->listSubFolders;
cmp_ok(@subf, '==', 9493,            'many subfolders');

@subf = $folder->listSubFolders(check => 1);
cmp_ok(@subf, '==', 6,               'few real subfolders');

@subf = $folder->listSubFolders(skip_empty => 1);
cmp_ok(@subf, '==', 5,               'few filled subfolders');

# get a subfolder

my $comp = $folder->openSubFolder('comp.lang.perl.misc');
ok(defined $comp,                    'open large subfolder');
cmp_ok($comp->messages, '==', 300,   '300 messages!');

my $message = $comp->message(10);
ok($message->head->isDelayed,        'delayed head');
ok($message->body->isDelayed,        'delayed body');

is($message->subject, 'search and replace problem', 'subject');
ok(! $message->head->isDelayed,      'realized head');
ok(! $message->body->isDelayed,      'realized body');
ok(! $folder->isModified);

#$message->print;

#use Mail::Box::MH;
#my $out = Mail::Box::MH->new(folder => "/tmp/abc", create => 1,
#  access => 'w') or die;

use Mail::Box::Mbox;
my $out = Mail::Box::Mbox->new(folder => "/tmp/abd", create => 1,
  access => 'w') or die;

$folder->copyTo($out);
ok(!$folder->isModified);
ok(!$comp->isModified);

exit 0;
