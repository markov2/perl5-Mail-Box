#!/usr/local/bin/perl -w

#
# Test threading on Mbox folders.
#

use strict;

use Test;
use File::Copy;

use lib '..';

use Mail::Box::Mbox;

BEGIN {plan tests => 1}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = 't/mbox.src';
my $src  = 't/mbox.cpy';

copy $orig, $src or die "Cannot create test folder.";

my $folder = Mail::Box::Mbox->new
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , take_headers => 'REAL'
  , access       => 'rw'
  , save_on_exit => 0
  );

die "Couldn't read $src." unless $folder;

my $out;
foreach (sort {$a->messageID cmp $b->messageID} $folder->threads)
{   $out .= $_->threadToString;
}
print $out;

ok($out eq <<'DUMP');
3.1K *- Re: converts new sharpen factors
2.9K *- Problem resizing images through perl script
1.5K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
3.2K 
2.8K Transparency question
3.9K RE: Transparency question
1.3K Re: Annotate problems (PR#298)
1.1K `- Re: Annotate problems (PR#298)
1.3K Re: your mail
1.2K `- Re: your mail
1.3K Re: your mail
1.8K Re: your mail
5.0K `- Re: your mail
2.6K New ImageMagick mailing list
1.9K Confirmation for subscribe magick-developer
644  `- Re: Confirmation for subscribe magick-developer
392  subscribe
 12K Welcome to magick-developer
2.6K Font metrics
2.9K *- Re: File Conversion From HTML to PS and TIFF
3.9K    `--*- Re: File Conversion From HTML to PS and TIFF
3.8K       `- Re: File Conversion From HTML to PS and TIFF
2.3K Undefined Symbol: SetWarningHandler
1.6K `- Re: Undefined Symbol: SetWarningHandler
2.0K mailing list archives
2.9K printing solution for UW 7.1
2.8K delegates.mgk set-up for unixware printing
3.2K core dump in simple ImageMagick example
2.7K `- Re: core dump in simple ImageMagick example
2.2K    `- Re: core dump in simple ImageMagick example
1.4K       `- Re: core dump in simple ImageMagick example
3.5K Core Dump on ReadImage
1.6K `- Re: Core Dump on ReadImage
4.8K RE: Transparency question
7.0K RE: Transparency question
8.7K RE: Transparency question
4.2K RE: jpeg2000 question
2.2K 
1.9K `- Re: your mail
2.5K    `- Re: your mail
1.7K Resize with Transparency
DUMP
