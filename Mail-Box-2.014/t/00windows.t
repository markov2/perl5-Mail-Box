#!/usr/bin/perl
# On Windows, the test mailbox must be have lines which are
# separated by CRLFs.  The mbox.src which is supplied is UNIX-style,
# so only has LF line-terminations.  In this script, this is
# translated.  The Content-Length of the messages is updated too.

use Test;

use strict;
use warnings;
use FileHandle;

BEGIN {
   unless($^O =~ m/^win/i)
   {   warn "requires MicroSoft Windows.\n";
       plan tests => 0;
       exit 0;
   }

   plan tests => 1;
}

chdir 't' if -d 't';   # started from level up.

my $src  = 'mbox.src';
my $dest = 'mbox.win';

open SRC,  '<', $src  or die "Cannot open $src to read: $!\n";
binmode SRC;
$/ = "\012";

open DEST, '>', $dest or die "Cannot open $src for writing: $!\n";
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

die "Errors in reading $src"  unless close SRC;
die "Errors in writing $dest" unless close DEST;

ok(1);
