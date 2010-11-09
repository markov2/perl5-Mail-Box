#!/usr/bin/env perl
#
# Test reading of dbx folders.
#

use strict;
use warnings;

use lib qw(. .. tests);
use Tools;

use Test::More;
use File::Compare;
use File::Temp qw(tempdir tempfile);

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

   plan tests => 22;
}

my $test = 'MBOX';   # folder to copy to
#my $test = 'MH';

my $temp = 'dbxtest';

sub be_sure_its_clean()
{
    if($test eq 'MH') { clean_dir $temp }
    else
    {   unlink $temp;
        clean_dir "$temp.d";
    }
}

be_sure_its_clean;
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

my $out;

if($test eq 'MH')
{   require Mail::Box::MH;
    $out = Mail::Box::MH->new(folder => $temp, create => 1,
        access => 'w');
}
else
{   require Mail::Box::Mbox;
    $out  = Mail::Box::Mbox->new(folder => $temp, create => 1,
        access => 'w', log => 'DEBUG');
}

die "Cannot create temporary folder $temp: $!\n" unless defined $out;

ok($folder->copyTo($out), "Copy succesful");
cmp_ok(scalar $out->messages, '==', scalar $folder->messages);
cmp_ok(scalar $out->messages, '==', 0);
ok(!$folder->isModified);
ok(!$comp->isModified);
$comp->close;
$out->close;
$folder->close;

be_sure_its_clean;
exit 0;
