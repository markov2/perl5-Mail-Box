
package Tools;
use strict;
use Exporter;
our @ISA    = 'Exporter';
our @EXPORT = qw/clean_dir unpack_mbox/;

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

# UNPACK_MBOX
# Unpack an mbox-file into an MH-directory.
# This skips message-nr 13 for testing purposes.

sub unpack_mbox($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    mkdir $dir;
    my $count = 1;

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

