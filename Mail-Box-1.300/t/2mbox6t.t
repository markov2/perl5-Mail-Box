#!/usr/local/bin/perl -w

#
# Test threading on Mbox folders.
#

use strict;

use Test;
use File::Copy;
use File::Spec;

use lib '..';
use Mail::Box::Manager;

BEGIN {plan tests => 16}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

my $orig = File::Spec->catfile('t', 'mbox.src');
my $src  = File::Spec->catfile('t', 'mbox.cpy');

copy $orig, $src
    or die "Cannot create test folder $src: $!\n";

my $mgr = Mail::Box::Manager->new;
ok($mgr);

my $folder = $mgr->open
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

my $threads = $mgr->threads(folder => $folder);

# First try message which is single.
my $single = $folder->messageID(
   '<200010041822.e94IMZr19712@mystic.es.dupont.com>');
ok($single);

my $start = $threads->threadStart($single);
ok($start);
ok($single->messageID eq $start->message->messageID);

my $message = $folder->messageID(
    '<NDBBJJFDMKFOAIFBEPPJIELLCBAA.cknoos@atg.com>');
ok($message);

my $this = $threads->thread($message);
ok($this);
ok($this->threadToString, <<'MIDDLE');
2.9K Problem resizing images through perl script
1.4K `- Re: Problem resizing images through perl script
3.1K    `- RE: Problem resizing images through perl script
1.6K       `- Re: Problem resizing images through perl script
MIDDLE

$start = $threads->threadStart($message);
ok($start);
ok($start->message->isa('Mail::Box::Message'));
ok($start->message->messageID ne $message->messageID);
ok($start->threadToString, <<'START');
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
START

$this->folded(1);
ok($start->threadToString, <<'FOLDED');
     *- [4] Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
FOLDED

$this->folded(0);
ok($start->threadToString, <<'START');
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
START

my $out = join '', map {$_->threadToString} $threads->sortedKnown;

my @lines = split "\n", $out;
pop @lines;
ok(@lines = $folder->messages);

ok($out eq <<'DUMP');
1.7K Resize with Transparency
2.8K *- Re: File Conversion From HTML to PS and TIFF
3.8K    `--*- Re: File Conversion From HTML to PS and TIFF
3.8K       `- Re: File Conversion From HTML to PS and TIFF
2.8K Transparency question
3.8K RE: Transparency question
4.7K RE: Transparency question
7.0K RE: Transparency question
8.7K RE: Transparency question
4.1K RE: jpeg2000 question
2.9K *- Problem resizing images through perl script
1.4K |  `- Re: Problem resizing images through perl script
3.1K |     `- RE: Problem resizing images through perl script
1.6K |        `- Re: Problem resizing images through perl script
3.3K `- Re: Convert HTM, HTML files to the .jpg format
2.2K Undefined Symbol: SetWarningHandler
1.6K `- Re: Undefined Symbol: SetWarningHandler
3.3K *- Re: watermarks/embossing
1.3K Re: Annotate problems (PR#298)
1.1K `- Re: Annotate problems (PR#298)
2.1K 
1.9K `- Re: your mail
2.5K    `- Re: your mail
3.2K 
1.3K Re: your mail
1.2K `- Re: your mail
1.3K Re: your mail
1.8K Re: your mail
4.9K `- Re: your mail
1.9K mailing list archives
2.8K printing solution for UW 7.1
2.7K delegates.mgk set-up for unixware printing
3.1K *- Re: converts new sharpen factors
2.5K New ImageMagick mailing list
340  subscribe
1.8K Confirmation for subscribe magick-developer
592  `- Re: Confirmation for subscribe magick-developer
 12K Welcome to magick-developer
3.1K core dump in simple ImageMagick example
2.7K `- Re: core dump in simple ImageMagick example
2.1K    `- Re: core dump in simple ImageMagick example
1.3K       `- Re: core dump in simple ImageMagick example
3.4K Core Dump on ReadImage
1.5K `- Re: Core Dump on ReadImage
2.6K Font metrics
DUMP

