#!/usr/bin/perl

#
# Test creation/deletion and listing of folders.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

use Mail::Box::Mbox;
use Mail::Message::Construct;

use Tools;
use File::Copy;
use File::Spec;

BEGIN {plan tests => 24}

my $top  = File::Spec->catdir('folders', 'Mail');
clean_dir $top;

#
# Create a nice structure which looks like a set of mbox folders.
#

sub dir($;$)
{   my $dirname = shift;
    $dirname = File::Spec->catdir($dirname, shift) if @_;

    die "Cannot create $dirname: $!\n"
        unless -d $dirname || mkdir $dirname, 0700;

    $dirname;
}

sub folder($$;$)
{   my $filename = File::Spec->catfile(shift, shift);

    my $content  = shift || $src;
    copy $content, $filename
       or die "Cannot copy $content to $filename: $!\n";
}

dir $top;
folder $top, "f1", $0;
folder $top, "f2";
folder $top, "f3", File::Spec->devnull;   # empty file

my $dir = dir $top, "sub1";
folder $dir, "s1f1";
folder $dir, "s1f2";
folder $dir, "s1f3";

dir $top, "sub2";                 # empty dir

folder $top, "f4";
$dir = dir $top, "f4.d";          # fake subfolder
folder $dir, "f4f1";
folder $dir, "f4f2";
folder $dir, "f4f3";

my $success =
   cmplists [ sort Mail::Box::Mbox->listSubFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ];
ok($success,                            'Initial tree');
unless($success)
{   require File::Find;
    File::Find::find( { wanted => sub {print STDERR "$_\n" }
                      , no_chdir => 1
                      }, $top);
    exit 1;
}

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders(folderdir => $top) ]
          , [ qw/f1 f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders
                     ( folderdir  => $top
                     , skip_empty => 1
                     ) ]
          , [ qw/f1 f2 f4 sub1/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders
                     ( folderdir  => $top
                     , check      => 1
                     ) ]
          , [ qw/f2 f3 f4 sub1 sub2/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders
                     ( folderdir  => File::Spec->catfile($top, "f4.d")
                     ) ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders
                     ( folderdir  => $top
                     , folder     => "=f4.d"
                     )
            ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

ok(cmplists [ sort Mail::Box::Mbox->listSubFolders
                     ( folder => File::Spec->catfile($top, "f4")) ]
          , [ qw/f4f1 f4f2 f4f3/ ]
  );

#
# Open a folder in a sub-dir which uses the extention.
#

my $folder = Mail::Box::Mbox->new
  ( folderdir   => $top
  , folder      => '=f4/f4f2'
  , lock_type   => 'NONE'
  );

ok($folder);
cmp_ok($folder->messages, "==", 45);
$folder->close;

#
# Open a new folder.
#

ok(! -f File::Spec->catfile($top, 'f4', 'newfolder'));
Mail::Box::Mbox->create('=f4/newfolder', folderdir => $top);
ok(-f File::Spec->catfile($top, "f4.d", "newfolder"));

$folder = Mail::Box::Mbox->new
  ( folderdir   => $top
  , folder      => '=f4/newfolder'
  , access      => 'rw'
  , lock_type   => 'NONE'
  );

ok($folder);
cmp_ok($folder->messages, "==", 0);

my $msg = Mail::Message->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , data    => [ "a short message\n", "of two lines.\n" ]
  );

$folder->addMessage($msg);
cmp_ok($folder->messages, "==", 1);

$folder->close;
ok(-s File::Spec->catfile($top, 'f4.d', 'newfolder'));

#
# Delete a folder.
#

$folder = Mail::Box::Mbox->new
  ( folderdir   => $top
  , folder      => '=f4'
  , access      => 'rw'
  , lock_type   => 'NONE'
  );

ok(-f File::Spec->catfile($top, "f4"));
$folder->delete;
$folder->close;
ok(! -f File::Spec->catfile($top, "f4")); 
ok(! -d File::Spec->catfile($top, "f4.d")); 

#
# Write a folder, but at the same place is a subdir.  The subdir should
# be moved to a name ending on `.d'
#

my $sub1 = File::Spec->catfile($top, "sub1"); 
ok(-d $sub1);
Mail::Box::Mbox->create('=sub1', folderdir => $top);
ok(-d File::Spec->catfile($top, "sub1.d")); 

ok(-f $sub1); 
ok(-z $sub1); 

$folder = Mail::Box::Mbox->new
  ( folderdir   => $top
  , folder      => '=sub1'
  , access      => 'rw'
  , lock_type   => 'NONE'
  );

my $msg2 = Mail::Message->build
  ( From    => 'me@example.com'
  , To      => 'you@anywhere.aq'
  , Subject => 'Just a try'
  , data    => [ "a short message\n", "of two lines.\n" ]
  );

$folder->addMessage($msg2);
cmp_ok($folder->messages, "==", 1);
$folder->close;
ok(-s $sub1);

clean_dir $top;
