
use strict;
package Tools;

use base 'Exporter';
our @EXPORT =
  qw/clean_dir unpack_mbox2mh unpack_mbox2maildir
     cmplists listdir
     $src $unixsrc $winsrc
     $fn  $unixfn  $winfn
     $cpy $cpyfn
     $raw_html_data
     $crlf_platform $windows
    /;

use File::Spec;
use Sys::Hostname;

our ($src, $unixsrc, $winsrc);
our ($fn,  $unixfn,  $winfn);
our ($cpy, $cpyfn);
our($crlf_platform, $windows);

BEGIN {
   $windows       = $^O =~ m/win32|cygwin/i;
   $crlf_platform = $windows;

   $unixfn  = 'mbox.src';
   $winfn   = 'mbox.win';
   $cpyfn   = 'mbox.cpy';
   $unixsrc = File::Spec->catfile('t', $unixfn);
   $winsrc  = File::Spec->catfile('t', $winfn);
   $cpy     = File::Spec->catfile('t', $cpyfn);

   ($src, $fn) = $windows ? ($winsrc, $winfn) : ($unixsrc, $unixfn);
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

our @maildir_names =
 (   '8000000.localhost.23'
 ,  '90000000.localhost.213'
 , '110000000.localhost.12'
 , '110000001.l.42'
 , '110000002.l.42'
 , '110000002.l.43'
 , '110000004.l.43'
 , '110000005.l.43'
 , '110000006.l.43:2,'
 , '110000007.l.43:2,D'
 , '110000008.l.43:2,DF'
 , '110000009.l.43:2,DFR'
 , '110000010.l.43:2,DFRS'
 , '110000011.l.43:2,DFRST'
 , '110000012.l.43:2,F'
 , '110000013.l.43:2,FR'
 , '110000014.l.43:2,FRS'
 , '110000015.l.43:2,FRST'
 , '110000016.l.43:2,DR'
 , '110000017.l.43:2,DRS'
 , '110000018.l.43:2,DRST'
 , '110000019.l.43:2,FS'
 , '110000020.l.43:2,FST'
 , '110000021.l.43:2,R'
 , '110000022.l.43:2,RS'
 , '110000023.l.43:2,RST'
 , '110000024.l.43:2,S'
 , '110000025.l.43:2,ST'
 , '110000026.l.43:2,T'
 , '110000027.l.43'
 , '110000028.l.43'
 , '110000029.l.43'
 , '110000030.l.43'
 , '110000031.l.43'
 , '110000032.l.43'
 , '110000033.l.43'
 , '110000034.l.43'
 , '110000035.l.43'
 , '110000036.l.43'
 , '110000037.l.43'
 , '110000038.l.43'
 , '110000039.l.43'
 , '110000040.l.43'
 , '110000041.l.43'
 , '110000042.l.43'
 );
 
sub unpack_mbox2maildir($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    die unless @maildir_names==45;

    mkdir $dir or die;
    mkdir File::Spec->catfile($dir, 'cur') or die;
    mkdir File::Spec->catfile($dir, 'new') or die;
    mkdir File::Spec->catfile($dir, 'tmp') or die;
    my $msgnr = 0;

    open FILE, $file or die;
    open OUT, '>', File::Spec->devnull;

    my $last_empty = 0;

    while(<FILE>)
    {   if( m/^From / )
        {   close OUT;
            my $now      = time;
            my $hostname = hostname;

            my $msgfile  = File::Spec->catfile($dir
              , ($msgnr > 40 ? 'new' : 'cur')
              , $maildir_names[$msgnr++]
              );

            open OUT, ">", $msgfile or die "Create $msgfile: $!\n";
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

#
# A piece of HTML text which is used in some tests.
#

our $raw_html_data = <<'TEXT';
<HTML>
<HEAD>
<TITLE>My home page</TITLE>
</HEAD>
<BODY BGCOLOR=red>

<H1>Life according to Brian</H1>

This is normal text, but not in a paragraph.<P>New paragraph
in a bad way.

And this is just a continuation.  When texts get long, they must be
auto-wrapped; and even that is working already.

<H3>Silly subsection at once</H3>
<H1>and another chapter</H1>
<H2>again a section</H2>
<P>Normal paragraph, which contains an <IMG
SRC=image.gif>, some
<I>italics with linebreak
</I> and <TT>code</TT>

<PRE>
And now for the preformatted stuff
   it should stay as it was
      even   with   strange blanks
  and indentations
</PRE>

And back to normal text...
<UL>
<LI>list item 1
    <OL>
    <LI>list item 1.1
    <LI>list item 1.2
    </OL>
<LI>list item 2
</UL>
</BODY>
</HTML>
TEXT
