#!/usr/bin/perl
# On Windows, the test mailbox must be have lines which are
# separated by CRLFs.  The mbox.src which is supplied is UNIX-style,
# so only has LF line-terminations.  In this script, this is
# translated.  The Content-Length of the messages is updated too.

use Test::More;

use strict;
use warnings;
use FileHandle;

use Tools;

BEGIN {
   plan tests => 1;
}

open SRC,  '<', $unixsrc  or die "Cannot open $unixsrc to read: $!\n";
binmode SRC;
$/ = "\012";

open DEST, '>', $winsrc or die "Cannot open $winsrc for writing: $!\n";
select DEST;

until(eof SRC)
{
    my ($lines, $bytes);

  HEADER:
    while(<SRC>)
    {   s/[\012\015]*$/\n/;

           if( m/^Content-Length\: / ) {$bytes = $' +0}
        elsif( m/^Lines\: /          ) {$lines = $' +0}
        elsif( m/^\s*$/              )
        {   # End of header
            if(defined $bytes && defined $lines)
            {   $bytes += $lines;
                print "Content-Length: $bytes\n";
            }

            print "Lines: $lines\n"
                if defined $lines;

            print "\n";
            last HEADER;
        }
        else {print}
    }

  BODY:
    while(<SRC>)
    {   s/[\012\015]*$/\n/;
        print;
        last BODY if m/^From /;
    }
}

die "Errors in reading $unixsrc"  unless close SRC;
die "Errors in writing $winsrc"   unless close DEST;

pass("Folder conversion complete");
