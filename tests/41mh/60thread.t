#!/usr/bin/perl

#
# Test threading of MH folders.
#

use Test::More;
use strict;
use warnings;

use Mail::Box::Manager;
use Tools;

use File::Spec;

BEGIN {plan tests => 4}

my $mhsrc = File::Spec->catfile('folders', 'mh.src');

clean_dir $mhsrc;
unpack_mbox2mh($src, $mhsrc);

my $mgr    = new Mail::Box::Manager;

my $folder = $mgr->open
  ( folder    => $mhsrc
  , lock_type => 'NONE'
  , extract   => 'LAZY'
  , access    => 'rw'
  );

my $threads = $mgr->threads(folder => $folder);

cmp_ok($threads->known , "==",  0);

my @all = $threads->sortedAll;
cmp_ok(@all , "==",  28);

my $out = join '', map {$_->threadToString} @all;

my @lines = split "\n", $out;
pop @lines;
ok(@lines = $folder->messages);

compare_thread_dumps($out, <<'DUMP', 'sort thread full dump');
1.3K Resize with Transparency
1.2K *- Re: File Conversion From HTML to PS and TIFF
2.1K    `--*- Re: File Conversion From HTML to PS and TIFF
2.1K       `- Re: File Conversion From HTML to PS and TIFF
1.4K Transparency question
2.4K RE: Transparency question
3.3K RE: Transparency question
5.5K RE: Transparency question
7.2K RE: Transparency question
2.7K RE: jpeg2000 question
1.2K *- Problem resizing images through perl script
820  |  `- Re: Problem resizing images through perl script
1.8K |     `- RE: Problem resizing images through perl script
1.0K |        `- Re: Problem resizing images through perl script
1.2K `- Re: Convert HTM, HTML files to the .jpg format
747  Undefined Symbol: SetWarningHandler
1.1K `- Re: Undefined Symbol: SetWarningHandler
1.8K *- Re: watermarks/embossing
307  Re: Annotate problems (PR#298)
573  `- Re: Annotate problems (PR#298)
1.0K 
1.4K `- Re: your mail
1.9K    `- Re: your mail
2.0K 
152  Re: your mail
686  `- Re: your mail
189  Re: your mail
670  Re: your mail
4.4K `- Re: your mail
552  mailing list archives
1.5K printing solution for UW 7.1
1.4K delegates.mgk set-up for unixware printing
1.4K *- Re: converts new sharpen factors
1.2K New ImageMagick mailing list
 27  subscribe
822  Confirmation for subscribe magick-developer
 63  `- Re: Confirmation for subscribe magick-developer
 11K Welcome to magick-developer
1.7K core dump in simple ImageMagick example
2.2K `- Re: core dump in simple ImageMagick example
882     `- Re: core dump in simple ImageMagick example
754        `- Re: core dump in simple ImageMagick example
2.0K Core Dump on ReadImage
1.0K `- Re: Core Dump on ReadImage
1.6K Font metrics
DUMP

clean_dir $mhsrc;
