#!/usr/local/bin/perl -w

#
# Test threading on Mbox folders.
#

use strict;

use Test;
use File::Copy;
use File::Spec;

use lib '..';
use Mail::Box::Mbox;

BEGIN {plan tests => 13}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mbox.cpy');

copy $orig, $src
    or die "Cannot create test folder $src: $!\n";

my $folder = Mail::Box::Mbox->new
  ( folder       => $src
  , lock_method  => 'NONE'
  , lazy_extract => 'ALWAYS'
  , take_headers => 'REAL'
  , access       => 'rw'
  , save_on_exit => 0
# , thread_timespan => 'EVER'
  );
ok($folder);

die "Couldn't read $src: $!\n"
   unless $folder;

# First try message which is single.
my $single = $folder->messageID(
   '<200010041822.e94IMZr19712@mystic.es.dupont.com>');
ok($single);
my $start = $single->thread;
ok($start);
ok($single->messageID eq $start->messageID);

my $message = $folder->messageID(
    '<NDBBJJFDMKFOAIFBEPPJIELLCBAA.cknoos@atg.com>');
ok($message);

$start = $message->thread;
ok($start->isa('Mail::Box::Message'));
ok($start);
ok($start->messageID ne $message->messageID);
ok($start->threadToString, <<'START');
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
START

ok($message->threadToString, <<'MIDDLE');
2.9K Problem resizing images through perl script
1.4K `- Re: Problem resizing images through perl script
3.1K    `- RE: Problem resizing images through perl script
1.6K       `- Re: Problem resizing images through perl script
MIDDLE

$message->folded(1);
ok($start->threadToString, <<'FOLDED');
     *- [4] Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
FOLDED

$message->folded(0);
ok($start->threadToString, <<'START');
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
START

my $out;
foreach (sort {$a->messageID cmp $b->messageID} $folder->threads)
{   $out .= $_->threadToString;
}

ok($out eq <<'DUMP');
3.1K *- Re: converts new sharpen factors
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
3.2K 
2.8K Transparency question
3.8K RE: Transparency question
1.3K Re: Annotate problems (PR#298)
1.1K `- Re: Annotate problems (PR#298)
1.3K Re: your mail
1.2K `- Re: your mail
1.3K Re: your mail
1.8K Re: your mail
4.9K `- Re: your mail
2.5K New ImageMagick mailing list
1.8K Confirmation for subscribe magick-developer
592  `- Re: Confirmation for subscribe magick-developer
340  subscribe
 12K Welcome to magick-developer
2.6K Font metrics
2.8K *- Re: File Conversion From HTML to PS and TIFF
3.8K    `--*- Re: File Conversion From HTML to PS and TIFF
3.8K       `- Re: File Conversion From HTML to PS and TIFF
2.2K Undefined Symbol: SetWarningHandler
1.6K `- Re: Undefined Symbol: SetWarningHandler
1.9K mailing list archives
2.8K printing solution for UW 7.1
2.7K delegates.mgk set-up for unixware printing
3.1K core dump in simple ImageMagick example
2.7K `- Re: core dump in simple ImageMagick example
2.1K    `- Re: core dump in simple ImageMagick example
1.3K       `- Re: core dump in simple ImageMagick example
3.4K Core Dump on ReadImage
1.5K `- Re: Core Dump on ReadImage
4.7K RE: Transparency question
7.0K RE: Transparency question
8.7K RE: Transparency question
4.1K RE: jpeg2000 question
2.1K 
1.9K `- Re: your mail
2.5K    `- Re: your mail
1.7K Resize with Transparency
DUMP
