
use strict;
package Tools;

use base 'Exporter';
our @EXPORT = qw/clean_dir unpack_mbox2mh unpack_mbox2maildir
                 cmplists listdir
                 $src $unixsrc $winsrc
                 $fn  $unixfn  $winfn
                 $cpy $cpyfn
                /;

use File::Spec;
use Sys::Hostname;

our ($src, $unixsrc, $winsrc);
our ($fn,  $unixfn,  $winfn);
our ($cpy, $cpyfn);

BEGIN {
   $unixfn  = 'mbox.src';
   $winfn   = 'mbox.win';
   $cpyfn   = 'mbox.cpy';
   $unixsrc = File::Spec->catfile('t', $unixfn);
   $winsrc  = File::Spec->catfile('t', $winfn);
   $cpy     = File::Spec->catfile('t', $cpyfn);
   ($src, $fn) = $^O =~ m/win/
            ? ($winsrc, $winfn)
            : ($unixsrc, $unixfn);
}

#
# CLEAN_DIR
# Clean a directory structure, typically created by unpack_mbox()
#

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

# UNPACK_MBOX2MH
# Unpack an mbox-file into an MH-directory.
# This skips message-nr 13 for testing purposes.

sub unpack_mbox2mh($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    mkdir $dir, 0700;
    my $count = 1;

    open FILE, $file or die;
    open OUT, '>', File::Spec->devnull;

    while(<FILE>)
    {   if( /^From / )
        {   close OUT;
            open OUT, ">$dir/".$count++ or die;
            $count++ if $count==13;  # skip 13 for test
            next;                    # from line not included in file.
        }
        print OUT;
    }

    close OUT;
    close FILE;
}

# UNPACK_MBOX2MAILDIR
# Unpack an mbox-file into an Maildir-directory.

sub unpack_mbox2maildir($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    mkdir $dir, 0700;
    my $unique = 1;

    open FILE, $file or die;
    open OUT, '>', File::Spec->devnull;

    while(<FILE>)
    {   if( /^From / )
        {   close OUT;
            my $now      = time;
            my $hostname = hostname;
            open OUT, ">$dir/cur/$now.$hostname.$unique" or die;
            $unique++;
            next;                    # from line not included in file.
        }
        print OUT;
    }

    close OUT;
    close FILE;
}

#
# Compare two lists.
#

sub cmplists($$)
{   my ($first, $second) = @_;
    return 0 unless @$first == @$second;
    for(my $i=0; $i<@$first; $i++)
    {   return 0 unless $first->[$i] eq $second->[$i];
    }
    1;
}

#
# List directory
# This removes '.' and '..'
#

sub listdir($)
{   my $dir = shift;
    opendir LISTDIR, $dir or return ();
    my @entities = grep !/^\.\.?$/, readdir LISTDIR;
    closedir LISTDIR;
    @entities;
}
