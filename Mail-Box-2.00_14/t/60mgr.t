#!/usr/bin/perl -w

#
# Test the folder manager
#

use strict;
use lib qw(. t /home/markov/MailBox2/fake);
use Mail::Box::Manager;
use Tools;

use Test;
use File::Spec;

warn "   * Various packages\n";

BEGIN {plan tests => 11}

my $src  = File::Spec->catfile('t', 'mbox.src');
my $new  = File::Spec->catfile('t', 'create');
unlink $new;

my $manager = Mail::Box::Manager->new;

my $folder  = $manager->open
  ( folder    => $src
  , folderdir => 't'
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  );

ok(defined $folder);
ok($folder->isa('Mail::Box::Mbox'));

my $warn;
{ local $SIG{__WARN__} = sub {$warn = join '', @_}; # ignore warning.
  my $second = $manager->open
    ( folder       => $src
    , lock_type    => 'NONE'
    );

  ok(!defined $second);
}
ok($warn eq "Folder t/mbox.src is already open.\n");

ok($manager->openFolders==1);

undef $warn;
# Test a creation.
{ local $SIG{__WARN__} = sub {$warn = join '', @_}; # ignore warning.
  my $n = $manager->open
    ( folder       => $new
    , folderdir    => 't'
    , type         => 'mbox'
    , lock_type    => 'NONE'
    );
  ok(! -f $new);
  ok(not defined $n);
}
ok(!defined $warn);

my $n = $manager->open
  ( folder       => $new
  , folderdir    => 't'
  , lock_type    => 'NONE'
  , type         => 'mbox'
  , create       => 1
  );
ok(-f $new);
ok($n);
ok(-z $new);

unlink $new;
exit 0;
