#!/usr/bin/perl

#
# Test threading on Mbox folders.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);
use Mail::Box::Manager;
use Tools;

use File::Copy;

BEGIN {plan tests => 23}

#
# We will work with a copy of the original to avoid that we write
# over our test file.
#

copy $src, $cpy
    or die "Cannot create test folder $cpy: $!\n";

my $mgr = Mail::Box::Manager->new;
ok($mgr);

my $folder = $mgr->open
  ( folder       => "=$cpyfn"
  , folderdir    => 'folders'
  , lock_type    => 'NONE'
  , extract      => 'LAZY'
  , access       => 'rw'
  , save_on_exit => 0
# , thread_timespan => 'EVER'
  );
ok($folder);

my $threads = $mgr->threads(folder => $folder);

# First try message which is single.
my $single = $folder->messageID(
   '<200010041822.e94IMZr19712@mystic.es.dupont.com>');
ok($single);
my $single2 = $folder->messageID(
   '200010041822.e94IMZr19712@mystic.es.dupont.com');
ok($single2);
is($single2, $single);
my $single3 = $folder->messageID(
   'garbage <200010041822.e94IMZr19712@mystic.es.dupont.com> trash');
ok($single3);
is($single3, $single);

my $start = $threads->threadStart($single);
ok($start);
is($single->messageID, $start->message->messageID);

my $message = $folder->messageID('NDBBJJFDMKFOAIFBEPPJIELLCBAA.cknoos@atg.com');
ok($message);

my $this = $threads->thread($message);
ok($this);
is($this->threadToString, <<'MIDDLE');
1.2K Problem resizing images through perl script
820  `- Re: Problem resizing images through perl script
1.8K    `- RE: Problem resizing images through perl script
1.0K       `- Re: Problem resizing images through perl script
MIDDLE

$start = $threads->threadStart($message);
ok(defined $start);
my $startmsg = $start->message;
ok(defined $startmsg);
isa_ok($startmsg, 'Mail::Message::Dummy');
isa_ok($startmsg, 'Mail::Message');
ok($startmsg->isDummy);
ok($startmsg->messageID ne $message->messageID);
is($start->threadToString, <<'START');
1.2K *- Problem resizing images through perl script
820  |  `- Re: Problem resizing images through perl script
1.8K |     `- RE: Problem resizing images through perl script
1.0K |        `- Re: Problem resizing images through perl script
1.2K `- Re: Convert HTM, HTML files to the .jpg format
START

$this->folded(1);
is($start->threadToString, <<'FOLDED');
     *- [4] Problem resizing images through perl script
1.2K `- Re: Convert HTM, HTML files to the .jpg format
FOLDED

$this->folded(0);
is($start->threadToString, <<'START');
1.2K *- Problem resizing images through perl script
820  |  `- Re: Problem resizing images through perl script
1.8K |     `- RE: Problem resizing images through perl script
1.0K |        `- Re: Problem resizing images through perl script
1.2K `- Re: Convert HTM, HTML files to the .jpg format
START

my $out   = join '', map {$_->threadToString} $threads->sortedKnown;

my @lines = split "\n", $out;
pop @lines;
ok(@lines = $folder->messages);

is($out, <<'DUMP');
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
