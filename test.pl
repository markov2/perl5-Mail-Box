#!/usr/bin/env perl

use warnings;
use strict;

use File::Spec;
use File::Basename;

use lib qw(tests lib);

# test env at home
$ENV{PERL5LIB} .= qw(:/home/markov/shared/perl/IMAPClient/lib);
delete $ENV{PERLIO};

use Config;
use Tools;             # test tools
use Mail::Reporter;    # to avoid 'too late for INIT'

use IO::Dir;
use TAP::Harness            ();
use TAP::Parser::Aggregator ();

# we use Test::More without a plan here, but we don't want
# Test::Builder to mess with the exit code
Test::More->builder->no_ending(1);

chdir 'tests'    ##### CHANGE DIR TO tests
   or die "Cannot go to test scripts directory: $!\n";

my $verbose = 0;
if(@ARGV && $ARGV[0] eq '-v')
{   $verbose = 1;
    shift @ARGV;
}

my $select_tests;
if(@ARGV)
{   my $pat = join '|', @ARGV;
    $select_tests   = qr/$pat/o;
}

# The versions of the following packages are reported to help understanding
# the environment in which the tests are run.  This is certainly not a
# full list of all installed modules.
my @show_versions = defined $select_tests ? ()
 : qw/Mail::Box Mail::Box::Parser::C
      User::Identity Object::Realize::Later MIME::Types
      TAP::Harness Encode MIME::Entity Mail::Internet HTML::FormatText
     /;

my $skip_tests = -f 'skiptests' || -f '../skiptests'
  || ($ENV{MAILBOX_RUN_TESTS} || 'yes') eq 'no';

#warn "SKIP? ", (-f 'skiptests' ? 'Y' : 'N'), (-f '../skiptests' ? 'Y' : 'N'),
#  "#$ENV{MAILBOX_RUN_TESTS}#", `pwd`;

sub package_of($);
sub testnames($);
sub run_in_harness(@);
sub report();
sub dl_format($@);

warn <<'WARN' unless $select_tests;

*
* Testing MailBox
WARN

if($skip_tests)
{   warn <<'WARN';
* Tests are disabled, because you said so when the Makefile was created.
* remove the file "skiptests" if you want to run them and/or clear
* environment variable MAILBOX_RUN_TESTS
*
WARN
    exit 0;
}

warn <<'WARN' unless $select_tests;
*
* Sometimes installing MailBox breaks because of the huge size
* of the whole package. Simply restarting the installation is in
* most cases enough to solve the problems.  You may require a new
* version of ExtUtils::MakeMaker.
*
* On *Windows* you will get a large number of failing tests, but they
* are usually harmless.  Please help me to get rit of them.
*

WARN

warn "Running on $^O ($Config{archname} $Config{osvers}), with Perl $]\n";

foreach my $package (@show_versions)
{   eval "require $package";

    my $report
      = !$@                    ? "version ". ($package->VERSION || 'unknown')
      : $@ =~ m/^Can't locate/ ? "not installed"
      : "reports error";

    warn "$package $report\n";
}
warn "\n";

#
# Get all the test-sets.
#

my $testdir = '.';
my $setdir  = IO::Dir->new($testdir);
die "Cannot open directory $testdir: $!"
     unless $setdir;

my @sets = sort grep { /^\d/ && -d File::Spec->catfile($testdir, $_) } 
                  $setdir->read;

$setdir->close;

my (%success, %skipped);
my $tests_run = 0;

foreach my $set (@sets)
{
    my $script = File::Spec->catfile($testdir, $set, 'Definition.pm');

    eval "require '$script'";
    if($@)
    {   warn "Errors while requiring $script:\n$@";
        next;
    }

    my $package  = package_of $set;

    if(my $reason = $package->skip)
    {   $skipped{$set} = $reason;
        printf "%-15s -- %s\n", $set, $reason;
        next;
    }

    my @tests = testnames $set;
    @tests    = grep { $_ =~ $select_tests } @tests
       if defined $select_tests;

    if(@tests)
    {   printf "%-15.15s -- %d %s %s\n", $set, scalar @tests,
           (@tests==1 ? "script; " : "scripts;"), $package->name;
    }
    elsif(defined $select_tests)  { ; }  # silence
    else
    {   printf "%-15.15s -- skip all tests for %s\n", $set, $package->name;
    }

    next unless @tests;

    $success{$set} = run_in_harness @tests;
    $tests_run += @tests;
}

my $critical = $tests_run ? report : 0;
exit $critical;

#
# PACKAGE_OF SET
# Returns the name of the package which contains details about the test-set.
#

sub package_of($) { "MailBox::Test::$_[0]::Definition" }

#
# TESTNAMES SET
# Returns a list of all the test for a certain test-set.
#

sub testnames($)
{   my $set = shift;
    my $dirname = File::Spec->catdir($testdir, $set);

    my $dir = IO::Dir->new($dirname)
        or return ();

    sort
        map { File::Spec->catfile($dirname, $_) }
            grep /\.t$/, $dir->read;
}

#
# RUN_IN_HARNESS @files
# Run the specified test files in a harness, but then the MailBox
# way doing things.
#

sub run_in_harness(@)
{   my @files = @_;
    return 1 unless @files;

    # cannot use $harness->runtests() because it always shows summary
    my $harness   = TAP::Harness->new( {verbosity => ($verbose ? 1 : 0)} );
    my $aggregate = TAP::Parser::Aggregator->new;
    $harness->aggregate_tests($aggregate, @files);
    not $aggregate->has_problems;
}

#
# PRINT_REPORT
#

sub report()
{
    print "--- Test report\n";

    my @success = sort grep {$success{$_}} keys %success;

    local $"    = ', ';
    dl_format(Success => @success) if @success;

    my @failed;
    my $critical = 0;

    foreach my $set (sort grep {not $success{$_}} keys %success)
    {   push @failed, $set;

        my $package = package_of $set;
        if($package->critical)
        {   $failed[-1] .= '(*)';
            $critical++;
        }
    }

    dl_format(Failure => @failed) if @failed;
    print "    Marked (*) are critical errors.\n" if $critical;

    my @skipped = sort keys %skipped;
    dl_format(Skipped => @skipped)     if @skipped;

    $critical;
}

#
# DL_FORMAT DT, DD-LIST
# Print in an HTML description-list fashion, with $" between the elements.
#

sub dl_format($@)
{   my $line = (shift) . ': ';
    my $elem = shift;

    while(defined $elem)
    {   $elem .= $" if @_;
        if(length($line) + length($elem) > 72)
        {   print "$line\n";
            $line = "    ";
        }
        $line .= $elem;
        $elem  = shift;
    }

    print "$line\n" if $line =~ /[^ ]/;
}
