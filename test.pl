#!/usr/bin/perl

use warnings;
use strict;

use lib qw(./lib ../lib tests);

use lib qw(/home/markov/shared/perl/UserIdentity/lib);
use lib qw(/home/markov/shared/perl/MimeTypes/lib);

use File::Spec;
use File::Basename;
use POSIX 'getcwd';

use Tools;             # test tools
use IO::Dir;

chdir 'tests' or die;    ##### CHANGE DIR TO tests

my $verbose = 0;
if(@ARGV && $ARGV[0] eq '-v')
{   $verbose = 1;
    shift @ARGV;
}

my $select_tests;
if(@ARGV)
{   my $pat = join '|', map { "\Q$_" } @ARGV;
    $select_tests   = qr/$pat/o;
}

sub package_of($);
sub testnames($);
sub run_in_harness(@);
sub report();
sub dl_format($@);
sub check_requirement($);
sub update_requirement($);
sub install_package($);

my $has_readkey;
BEGIN
{   eval "require Term::ReadKey";
    $has_readkey = not length $@;
}

sub ask($$)
{   my ($text, $default) = @_;
    print $text, " [$default] ";
    my $key;

    if($has_readkey)
    {   Term::ReadKey->import;
        ReadMode(3);   # cbreak mode
        $key = ReadKey(0) until defined($key);
        ReadMode(1);

        $key = $default if $key =~ m/\n/;
        print "$key\n";
    }
    else
    {   # No Term::ReadKey
        flush STDOUT;
        my $line = <STDIN>;
        $line    =~ m/(\S)/;
        $key     = $1 || $default;
    }

    $key;
}

my $default_install_answer = -t STDIN ? 'y' : 'n';

warn <<'WARN' unless $select_tests;

*
* Testing MailBox
*
* During the test phase (even if you do not run any tests), you will
* be asked to install optional modules.  You can always install those
* modules later without re-installing MailBox.
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

unless(defined $select_tests)
{   my $run = ask("Do you want to run the (large set of) tests?", "yes");
    $select_tests = "skip" unless $run =~ m/^y/i;
}

#
# Get all the test-sets.
#

my $testdir = '.';
my $setdir  = IO::Dir->new($testdir);
die "Cannot open directory $testdir: $!"
     unless $setdir;

my @sets = sort
              grep { /^\d/ && -d File::Spec->catfile($testdir, $_) } 
                 $setdir->read;

$setdir->close;

my @inc = map { "-I$_" } @INC;
my (%success, %skipped);
my $tests_run = 0;

foreach my $set (@sets)
{
    my $script = File::Spec->catfile($testdir, $set, 'Definition.pm');

    eval "require '$script'";
    if($@)
    {   warn "Errors while requiring $script:\n$@";
        warn "why am i here??? ",getcwd;
        next;
    }

    my $package  = package_of $set;

    if(my $reason = $package->skip)
    {   $skipped{$set} = $reason;
        printf "%-15s --- %s\n", $set, $reason;
        next;
    }

    my @tests = testnames $set;
    @tests    = grep { $_ =~ $select_tests } @tests
       if defined $select_tests;

    if(@tests)
    {   printf "%-15.15s -- run %2d %s %s\n", $set, scalar @tests,
           (@tests==1 ? "script; " : "scripts;"), $package->name;
    }
    elsif(defined $select_tests)  { ; }  # silence
    else
    {   printf "%-15.15s -- skip all tests; %s\n", $set, $package->name;
    }

    my @requires = $package->requires;
    check_requirement $_ foreach @requires;

    foreach my $req (@requires)
    {   update_requirement $req;
        check_requirement $req;    # do not always believe CPAN install
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
# way doin things.
#

sub run_in_harness(@)
{   my @files = @_;
    return 1 unless @files;

#   $ENV{PERL_DL_NONLAZY} = 1;
    my @inc = map { "-I$_" } @INC;

    system $^X, @inc
      , -e => 'use Test::Harness qw(&runtests $verbose);
               $verbose = shift @ARGV;
               my ($tot, $failed) = Test::Harness::_run_all_tests(@ARGV);
               exit not Test::Harness::_all_ok($tot);'
      , $verbose, @files;
    
    return $?==0;
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

#
# CHECK_REQUIREMENT HASH
# Check whether the right version of the optional packages are installed.
#

sub check_requirement($)
{   my $req = shift;

    return 1 if ${$req->{present}};

    my $package = $req->{package};

    local $_;   # evals are destroying $_ sometimes.
    eval "require $package";
    if($@)
    {   print "    package $package is not installed\n";
        return 0;
    }

    my $version = $req->{version};
    eval {$package->VERSION($version)};
    if($@)
    {   print "    package $package is too old; need version $version, installed is ".$package->VERSION.".\n";
        return 0;
    }

    ${$req->{present}} = 1;
}

#
# UPDATE_REQUIREMENT HASH
# If the requirement is not present, or too old, the user gets a chance to
# install it.
#

sub update_requirement($)
{   my $req = shift;

    return 1 if ${$req->{present}};

    my $package = $req->{package};
    my $module  = $req->{module} || $package;
    my $install = $default_install_answer;

    if($install eq 'a')
    {   $install = 'y';
    }
    else
    {   my $inmod   = $module ne $package ? " (in module $module)" : '';

        print "    package $package$inmod is optional.\n";
        if(my $reason  = $req->{reason})
        {   $reason =~ s/^/        /mg;
            print $reason;
        }

        my $key = ask("    do you want to install $package? yes/no/all", $install);

        if($key eq 'a')
        {   $default_install_answer = 'a';
            $install = 'y';
        }
        else
        {   $install = $key eq 'y' ? 'y' : 'n';
        }
    }

    return 0 unless $install eq 'y';

    install_package $package;
}

#
# INSTALL_PACKAGE PACKAGE
#

sub install_package($)
{   my $package = shift;
    local $_;

    print "    installing $package\n";
    my $pwd = getcwd;

    require CPAN;
    eval { CPAN::install($package) };

    chdir $pwd
       or warn "Cannot return to $pwd: $!n";
}
