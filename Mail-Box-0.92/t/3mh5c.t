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
use Mail::Box::MH;

BEGIN {plan tests => 19}

my $src = 't/mbox.src';
my $top = 't/Mail';

my $mbox = Mail::Box::Mbox->new
  ( folder      => $src
  , lock_method => 'NONE'
  );

#
# Create a nice structure which looks like a set of MH folders.
#

sub folder($;@)
{   my $dirname = shift;
    mkdir $dirname, 0700 || die unless -d $dirname;
    foreach (@_)
    {   open CREATE, ">$dirname/$_" or die;
        $mbox->message($_)->print(\*CREATE) if m/^\d+$/;
        close CREATE;
    }
}

folder $top;
folder "$top/f1", qw/a b c/;
folder "$top/f2", 1, 2, 3;       # only real folder
folder "$top/f3";                # empty folder
folder "$top/sub1";
folder "$top/sub1/s1f1";
folder "$top/sub1/s1f2";
folder "$top/sub1/s1f3";
folder "$top/sub2";               # empty dir
folder "$top/f4", 1, 2, 3;
folder "$top/f4/f4f1";
unpack_mbox "t/mbox.src", "$top/f4/f4f2";
folder "$top/f4/f4f3";

ok(cmplists [ sort Mail::Box::MH->listFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listFolders
                     ( folderdir  => $top
                     , skip_empty => 1
                     ) ]
          , [ qw/f2 f4 sub1/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listFolders
                     ( folderdir  => $top
                     , check      => 1
                     ) ]
          , [ qw/f2 f4/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listFolders
                     ( folderdir  => $top
                     , folder     => "=f4"
                     )
            ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::MH->listFolders(folderdir  => "$top/f4") ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

#
# Open a folder in a sub-dir which uses the extention.
#

my $folder = Mail::Box::MH->new
  ( folderdir => $top
  , folder    => '=f4/f4f2'
  );

ok($folder);
ok($folder->messages==45);
$folder->close;

#
# Open a new folder.
#

ok(! -d "$top/f4/newfolder");
Mail::Box::MH->create('=f4/newfolder', folderdir  => $top);
ok(-d "$top/f4/newfolder");

$folder = Mail::Box::MH->new
  ( folderdir  => $top
  , folder     => '=f4/newfolder'
  , access     => 'rw'
  , keep_index => 1
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
ok(-f "$top/f4/newfolder/1");

opendir DIR, "$top/f4/newfolder" or die;
my @all = grep !/^\./, readdir DIR;
closedir DIR;
ok(@all==1);

open SEQ, "$top/f4/newfolder/.mh_sequences" or die;
my @seq = <SEQ>;
ok(@seq==1);
ok($seq[0],"unseen: 1\n");

#
# Delete a folder.
#

$folder = Mail::Box::MH->new
  ( folderdir => $top
  , folder    => '=f4'
  , access    => 'rw'
  );

ok(-d "$top/f4");
$folder->delete;
$folder->close;
ok(! -d "$top/f4");

clean_dir $top;
