use strict;
package Tools;

use lib qw(lib ../lib);
use base 'Exporter';
use File::Copy 'copy';
use List::Util 'first';
use IO::File;            # to overrule open()

our @EXPORT =
  qw/clean_dir copy_dir
     unpack_mbox2mh unpack_mbox2maildir
     compare_lists listdir
     compare_message_prints reproducable_text
     compare_thread_dumps
     start_pop3_server start_pop3_client

     $folderdir
     $src $unixsrc $winsrc
     $fn  $unixfn  $winfn
     $cpy $cpyfn
     $raw_html_data
     $crlf_platform $windows
    /;

use Test::More;
use File::Spec;
use Sys::Hostname;
use Cwd;

our ($logfile, $folderdir);
our ($src, $unixsrc, $winsrc);
our ($fn,  $unixfn,  $winfn);
our ($cpy, $cpyfn);
our ($crlf_platform, $windows);

BEGIN {
   $windows       = $^O =~ m/mswin32|cygwin/i;
   $crlf_platform = $windows;

   $folderdir     = -d 'folders' ? 'folders'
                  : File::Spec->catdir('tests','folders');

   $logfile = File::Spec->catfile(getcwd(), 'run-log');
   $unixfn  = 'mbox.src';
   $winfn   = 'mbox.win';
   $cpyfn   = 'mbox.cpy';

   $unixsrc = File::Spec->catfile('folders', $unixfn);
   $winsrc  = File::Spec->catfile('folders', $winfn);
   $cpy     = File::Spec->catfile('folders', $cpyfn);

   ($src, $fn) = $crlf_platform ? ($winsrc, $winfn) : ($unixsrc, $unixfn);

   # IO::File::open() is wrapped, because starting with 1.11 (Perl 5.8.7)
   # it cannot open files with relative pathnames when tainting checks are
   # enabled.  I want to test relative folder names!!
   #
   # workaround: turn the relative path to an absolute
   # one here, then untaint it
   # Idea based on a contribution by Niko Tyni

   my $old_open = \&IO::File::open;
   no warnings 'redefine';
   *IO::File::open = sub {
      my $fh = shift;
      if(ref $_[0] eq 'SCALAR') { print ${$_[0]} }
      return $old_open->($fh, @_) if ref $_[0];

      my $file = File::Spec->rel2abs(shift);
      $file =~ /^(.*)$/;   # untaint
      $old_open->($fh, $1, @_);
   }
}

#
# CLEAN_DIR
# Clean a directory structure, typically created by unpack_mbox()
#

sub clean_dir($);
sub clean_dir($)
{   my $dir = shift;
    opendir DIR, $dir or return;

    my @items = map { m/(.*)/ && "$dir/$1" }   # untainted
                    grep !/^\.\.?$/, readdir DIR;
    foreach (@items)
    {   if(-d)  { clean_dir $_ }
        else    { unlink $_ }
    }

    closedir DIR;
    rmdir $dir;
}

#
# COPY_DIR FROM, TO
# Copy directory to other place (not recursively), cleaning the
# destination first.
#

sub copy_dir($$)
{   my ($orig, $dest) = @_;

    clean_dir($dest);

    mkdir $dest
        or die "Cannot create copy destination $dest: $!\n";

    opendir ORIG, $orig
        or die "Cannot open directory $orig: $!\n";

    foreach my $name (map { !m/^\.\.?$/ && m/(.*)/ ? $1 : () } readdir ORIG)
    {   my $from = File::Spec->catfile($orig, $name);
        next if -d $from;

        my $to   = File::Spec->catfile($dest, $name);
        copy($from, $to) or die "Couldn't copy $from,$to: $!\n";
    }

    close ORIG;
}

# UNPACK_MBOX2MH
# Unpack an mbox-file into an MH-directory.
# This skips message-nr 13 for testing purposes.
# Blanks before "From" are removed.

sub unpack_mbox2mh($$)
{   my ($file, $dir) = @_;
    clean_dir($dir);

    mkdir $dir, 0700;
    my $count = 1;
    my $blank;

    open FILE, $file or die;
    open OUT, '>', File::Spec->devnull;

    while(<FILE>)
    {   if( /^From / )
        {   close OUT;
            undef $blank;
            open OUT, ">$dir/".$count++ or die;
            $count++ if $count==13;  # skip 13 for test
            next;                    # from line not included in file.
        }

        print OUT $blank
            if defined $blank;

        if( m/^\015?\012$/ )
        {   $blank = $_;
            next;
        }

        undef $blank;
        print OUT;
    }

    close OUT;
    close FILE;
}

# UNPACK_MBOX2MAILDIR
# Unpack an mbox-file into an Maildir-directory.

our @maildir_names =
 (   '8000000.localhost.23:2,'
 ,  '90000000.localhost.213:2,'
 , '110000000.localhost.12:2,'
 , '110000001.l.42:2,'
 , '110000002.l.42:2,'
 , '110000002.l.43:2,'
 , '110000004.l.43:2,'
 , '110000005.l.43:2,'
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
 , '110000027.l.43:2,'
 , '110000028.l.43:2,'
 , '110000029.l.43:2,'
 , '110000030.l.43:2,'
 , '110000031.l.43:2,'
 , '110000032.l.43:2,'
 , '110000033.l.43:2,'
 , '110000034.l.43:2,'
 , '110000035.l.43:2,'
 , '110000036.l.43:2,'
 , '110000037.l.43:2,'
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
    my $blank;

    while(<FILE>)
    {   if( m/^From / )
        {   close OUT;
            undef $blank;
            my $now      = time;
            my $hostname = hostname;

            my $msgfile  = File::Spec->catfile($dir
              , ($msgnr > 40 ? 'new' : 'cur')
              , $maildir_names[$msgnr++]
              );

            open OUT, ">", $msgfile or die "Create $msgfile: $!\n";
            next;                    # from line not included in file.
        }

        print OUT $blank
            if defined $blank;

        if( m/^\015?\012$/ )
        {   $blank = $_;
            next;
        }

        undef $blank;
        print OUT;
    }

    close OUT;
    close FILE;
}

#
# Compare two lists.
#

sub compare_lists($$)
{   my ($first, $second) = @_;
#warn "[@$first]==[@$second]\n";
    return 0 unless @$first == @$second;
    for(my $i=0; $i<@$first; $i++)
    {   return 0 unless $first->[$i] eq $second->[$i];
    }
    1;
}

#
# Compare the text of two messages, rather strict.
# On CRLF platforms, the Content-Length may be different.
#

sub compare_message_prints($$$)
{   my ($first, $second, $label) = @_;

    if($crlf_platform)
    {   $first  =~ s/Content-Length: (\d+)/Content-Length: <removed>/g;
        $second =~ s/Content-Length: (\d+)/Content-Length: <removed>/g;
    }

    is($first, $second, $label);
}

#
# Strip message text down the things which are the same on all
# platforms and all situations.
#

sub reproducable_text($)
{   my $text  = shift;
    my @lines = split /^/m, $text;
    foreach (@lines)
    {   s/((?:references|message-id|date|content-length)\: ).*/$1<removed>/i;
        s/boundary-\d+/boundary-<removed>/g;
    }
    join '', @lines;
}

#
# Compare two outputs of thread details.
# On CRLF platforms, the reported sizes are ignored.
#

sub compare_thread_dumps($$$)
{   my ($first, $second, $label) = @_;

    if($crlf_platform)
    {   $first  =~ s/^..../    /gm;
        $second =~ s/^..../    /gm;
    }

    is($first, $second, $label);
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
# Start POP3 server for 43pop3 tests
#

sub start_pop3_server($;$)
{  my $popbox  = shift;
   my $setting = shift || '';

   my $serverscript = File::Spec->catfile('43pop3', 'server');

   # Some complications to find-out $perl, which must be absolute and
   # untainted for perl5.6.1, but not for the other Perl's.
   my $perl   = $^X;
   unless(File::Spec->file_name_is_absolute($perl))
   {   my @path = split /\:|\;/, $ENV{PATH};
       $perl    = first { -x $_ }
                      map { File::Spec->catfile($_, $^X) }
                           @path;
   }

   $perl =~ m/(.*)/;
   $perl = $1;

   %ENV = ();

   open(my $server, "$perl $serverscript $popbox $setting|")
       or die "Could not start POP3 server\n";

   my $line  = <$server>;
   my $port  = $line =~ m/(\d+)/ ? $1
     : die "Did not get port specification, but '$line'";

   ($server, $port);
}

#
# START_POP3_CLIENT PORT, OPTIONS
#

sub start_pop3_client($@)
{   my ($port, @options) = @_;
    require Mail::Transport::POP3;
    
    Mail::Transport::POP3->new
     ( hostname => '127.0.0.1'
     , port     => $port
     , username => 'user'
     , password => 'password'
     , @options
     );
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

1;
