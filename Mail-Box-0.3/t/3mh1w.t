
use Test;
use File::Compare;
use File::Copy;
use lib '..';
use strict;

use Mail::Box::MH;
use Mail::Box::Mbox;

BEGIN {plan tests => 9}

my $orig = 't/mbox.src';
my $src = 't/mh.src';

sub clean_dir($);
sub clean_dir($)
{   my $dir = shift;
    opendir DIR, $dir or return;

    foreach (map { "$dir/$_" } grep !/^\.\.?$/, readdir DIR)
    {   if(-d)  { clean_dir $_ }
        else    { unlink $_ }
    }

    closedir DIR;
    rmdir $dir;
}

sub unpack_file($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    mkdir $dir;
    my $count = 0;

    open FILE, $file or die;
    open OUT, '/dev/null';

    while(<FILE>)
    {   if( /^From / )
        {   close OUT;
            open OUT, '>', "$dir/".$count++ or die;
            $count++ if $count==13;  # skip 13 for test
            next;                    # from line not included in file.
        }
        print OUT;
    }

    close OUT;
    close FILE;
}

#
# Unpack the file-folder.
#

unpack_file($orig, $src);

my $folder = new Mail::Box::MH
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , access       => 'rw'
  , keep_index   => 1
  );

ok(defined $folder);

# We skipped message number 13 in the production, but that shouldn't
# distrub things.

ok($folder->messages==45);

# Test lazy extract.

my $parsed = 0;
foreach ($folder->messages)
{  $parsed++ if $_->isParsed;
}
ok($parsed==0);

# Test subjects
# This shouldn't cause any parsings: we do lazy extract, but Mail::Box
# will always take the `Subject' header for us.

my @subjects = map { chomp; $_ }
                  map {$_->head->get('subject') || '<undef>' }
                     $folder->messages;

$parsed = 0;
foreach ($folder->messages)
{  $parsed++ if $_->isParsed;
}
ok($parsed==0);

#
# The subjects must be the same as from the original Mail::Box::Mbox
# There are some differences with new-lines at the end of headerlines
#

my $mbox = Mail::Box::Mbox->new
  ( folder      => $orig
  , lock_method => 'NONE'
  , access      => 'r'
  );

my @fsubjects = map { chomp; $_ }
                   map {$_->head->get('subject') || '<undef>'}
                      $mbox->messages;

my (%subjects);
$subjects{$_}++ foreach @subjects;
$subjects{$_}-- foreach @fsubjects;

my $missed = 0;
foreach (keys %subjects)
{   $missed++ if $subjects{$_};
    warn "Still left: $_ ($subjects{$_}x)\n" if $subjects{$_};
}
ok(!$missed);

#
# Check if we can load a body.
#

my $msg3 = $folder->message(3);
ok(not $msg3->isParsed);

my $body = $msg3->body;
ok(defined $body);
ok(@$body==43);       # check expected number of lines in message 3.
ok($msg3->isParsed);

$folder->write;

clean_dir $src;
