#!/usr/local/bin/perl -w

#
# Test creation/deletion and listing of folders.
#

use strict;

use Test;
use File::Copy;

use lib '..', 't';
use Tools;

use Mail::Box::Mbox;

BEGIN {plan tests => 17}

my $top = 't/Mail';
my $real = 't/mbox.src';

#
# Create a nice structure which looks like a set of mbox folders.
#

sub dir($)
{   my $dirname = shift;
    return if -d $dirname;
    mkdir $dirname, 0700 || die;
}

sub folder($;$)
{   my $filename = shift;
    my $content  = shift || 'Makefile';
    copy $content, $filename || die;
}

dir $top;
folder "$top/f1";
folder "$top/f2", $real;         # only real folder
folder "$top/f3", "/dev/null";   # empty file
dir "$top/sub1";
folder "$top/sub1/s1f1";
folder "$top/sub1/s1f2";
folder "$top/sub1/s1f3";
dir "$top/sub2";                 # empty dir
folder "$top/f4";
dir "$top/f4.d";                 # fake subfolder
folder "$top/f4.d/f4f1";
folder "$top/f4.d/f4f2", $real;
folder "$top/f4.d/f4f3";

ok(cmplists [ sort Mail::Box::Mbox->listFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders
                     ( folderdir  => $top
                     , skip_empty => 1
                     ) ]
          , [ qw/f1 f2 f4 sub1/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders
                     ( folderdir  => $top
                     , check      => 1
                     ) ]
          , [ qw/f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders(folderdir  => "$top/f4.d") ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders
                     ( folderdir  => $top
                     , folder     => "=f4.d"
                     )
            ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listFolders(folderdir  => "$top/f4") ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

#
# Open a folder in a sub-dir which uses the extention.
#

my $folder = Mail::Box::Mbox->new
  ( folderdir => $top
  , folder    => '=f4/f4f2'
  );

ok($folder);
ok($folder->messages==45);
$folder->close;

#
# Open a new folder.
#

$folder = Mail::Box::Mbox->new
  ( folderdir => $top
  , folder    => '=f4/newfolder'
  , access    => 'rw'
  );

ok($folder);
ok($folder->messages==0);

my $msg = MIME::Entity->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , Data    => [ "a short message\n", "of two lines.\n" ]
  );

$folder->addMessage($msg);
$folder->modifications(+1);
ok($folder->messages==1);
$folder->close;
ok(-s "$top/f4.d/newfolder");

#
# Write a folder, but at the same place is a subdir.  The subdir should
# be moved to a name ending on `.d'
#

$folder = Mail::Box::Mbox->new
  ( folderdir => $top
  , folder    => '=sub1'
  , access    => 'rw'
  );

$folder->addMessage($msg);
$folder->modifications(+1);
ok($folder->messages==1);
$folder->close;
ok(-d "$top/sub1.d");
ok(-s "$top/sub1");
ok(-f "$top/sub1");

clean_dir $top;
