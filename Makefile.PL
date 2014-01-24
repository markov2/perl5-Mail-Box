use ExtUtils::MakeMaker;

require 5.006_001;

use IO::Handle;

my $VERSION = '2.111';

# Usually, Scalar::Util is installed (in core since perl 5.8.0)
# However, sometimes it is (incorrectly) installed without XS, but as
# plain module.  In that case, Scalar::Util must be reinstalled.

eval { require Scalar::Util };
unless($@)
{   eval "Scalar::Util->import('dualvar')";
    if($@ =~ m/only.*XS/)
    {   warn <<'WARN';

!!!! WARNING !!!! On your system, the module Scalar::Util is installed
!!!! WARNING !!!! without use of XS.  This means that critical functionality
!!!! WARNING !!!! is missing.  Reinstall the module and be sure to get the
!!!! WARNING !!!! correct installation.
!!!! WARNING !!!!    perl -MCPAN -e 'shell'
!!!! WARNING !!!!       > force install Scalar::Util

WARN
    }
}

my @optional =
( 

#Not mainted, hence disabled for 2.084.
#  [ Mail::Box::Parser::C => '3.006'
#  , reason => <<'REASON', warning => <<'WARN' ]
#Speeds-up reading mail folders, though most time is consumed by
#Perl's administration of the processed data.
#REASON
#This module contains XS code, so you need a C compiler.
#WARN

# [ Mail::Transport::Dbx => '0.04', reason  => <<'REASON' ]
# The wrapper to the Outlook's dbx files consists of a c-library
# named libdbx (website http://sourceforge.net/project/ol2mbox/),
# and a wrapper which is distributed separately from Mail::Box.
# You get read-only access to the dbx folders.
# REASON

#, [ Mail::SpamAssassin => '2.00', reason  => <<'REASON', warning => <<'WARN' ]
#Searching for spam in a mail folder needs the popular spam killer.
#REASON
#This distr is large: installing will take quite a while. You
#can install it later.  When your CPAN cache is small, this may
#break your Mail::Box installing process.
#WARN

  [ Mail::IMAPClient => '3.22', reason => <<'REASON' ]
Required for IMAP4 support.
REASON

, [ Mail::Internet => '2.01', distr => 'MailTools', reason  => <<'REASON' ]
Many existing e-mail applications use Mail::Internet objects.  If
you want automatic conversions for compatibility, you need this.
REASON

, [ MIME::Entity => '3.0', distr  => 'MIME::Tools', reason  => <<'REASON' ]
MIME::Entity extends Mail::Internet messages with multipart handling
and composition.  Install this when you want compatibility with
distrs which are based on this kind of messages.
REASON

, [ HTML::TreeBuilder => '3.13', reason => <<'REASON' ]
The tree builder is used by the HTML::Format* packages.
Version 3.12 is wrong, so you should install a newer version
if you want smart html conversions.
REASON

, [ Time::HiRes => '1.51', reason => <<'REASON' ]
When installed, unique message-ids will be created using gettimeofday.
Otherwise, generated message-ids will not be thread/fork safe.
REASON

, [ HTML::FormatText => '2.01', distr => 'HTML::FormatText'
  , reason => <<'REASON' ]
Plug-in which converts HTML to Postscript or plain text.
REASON
);

my %prereq =
 ( Date::Format   => 0
 , Date::Parse    => 0.0
 , Digest::HMAC_MD5 => 0.0
 , Encode         => 2.26
 , Errno          => 0.0
 , File::Remove   => '0.20'
 , File::Spec     => 0.7
 , IO::Scalar     => 0.0
 , Mail::Address  => 0.0
 , MIME::Base64   => 0.0
 , MIME::Types    => 1.004
 , Object::Realize::Later => 0.19
 , Scalar::Util   => 1.13
 , Sys::Hostname  => 0.0
 , TAP::Harness   => '3.00'
 , Test::More     => 0.47
 , Test::Pod      => '1.00'
 , Time::Zone     => 0
 , URI            => 1.23
 , User::Identity => '0.94'
 , Devel::GlobalDestruction => 0.09
 );

my $default_install_answer
     = $ENV{MAILBOX_INSTALL_OPTIONALS}
    || $ENV{INSTALL_MAILBOX_OPTIONALS};      # deprecated

print <<'INTRO';
*
**** Installing MailBox
*
INTRO

print <<'REQUIRED';

* First, I will check the sanity of all required modules... sometimes
* they do not load, for instance if you have installed a new release
* of Perl without upgrading the libraries.

REQUIRED

my @errors;
foreach my $module (sort keys %prereq)
{   my $reqversion = $prereq{$module};
    eval "require $module";

    if($@ && $@ =~ m/^Can't locate /)
    {   print "    $module is not yet installed\n" }
    elsif($@)
    {   print "    $module produced an error:\n$@";
        push @errors, $module;
    }
    elsif($module->VERSION < $reqversion)
    {   print "    $module version ",$module->VERSION
            , " is outdated; requires $reqversion\n";
    }
    else
    {   print "    $module version ",$module->VERSION
            , " is ok (required is $reqversion)\n";
    }
}

if($errors)
{   die <<'FIX';
*** ERROR! You have to install @errors manually,
*** before you can retry to install MailBox.
FIX
    exit 1;
}

print <<'OPTIONAL';

* Now, let me ask you whether you want some optional modules to be
* installed as well.  You can always install these modules later, by
* hand, without a need to re-install MailBox.
*
OPTIONAL

foreach my $optional (sort {$a->[0] cmp $b->[0]} @optional)
{   my ($module, $version, %args) = @$optional;
    my $requirements = $args{requires} || sub {1};
    next unless $requirements->();

    if($module eq 'MIME::Entity')
    {   # work-around for awkward development situation at home,
        # where the VERSION string is not in the development pre-release.
        no warnings;
        eval "require Mail::Internet";
        unless($@)
        {   $Mail::Internet::VERSION ||= '2.00';
            $Mail::Field::VERSION    ||= '2.00';
            $Mail::Header::VERSION   ||= '2.00';
        }
    }

#   print "\n";
    eval "require $module";
    if($@)
    {   if($@ =~ m/^Can't locate /)
             { print "**** Optional $module is not installed\n"        }
        else { print "**** Optional $module compilation failed:\n$@\n" }
    }
    elsif(eval '$module->VERSION($version)' && $@)
    {   my $error = $@ || '';
        $error =~ s/[\r\n]+$//;
        print "**** Optional $module too old: requires $version but is ",
            $module->VERSION,";$error\n";
    }
    else
    {   my $v = $module->VERSION;
        my $r = $v eq $version ? ''
              : $version eq 0  ? " (any version will do)"
              :                  " (at least $version required)";

        print "**** Found optional $module version $v$r\n";
        next;
    }

    my $reason = $args{reason};
    $reason =~ s/^/     /gm;
    $reason =~ s/\A    /Use:/;
    print $reason;

    if(my $warn = $args{warning})
    {   $warn =~ s/^/     /gm;
        $warn =~ s/\A    /WARN/;
        print $warn;
    }
    
    my $install = $default_install_answer
     || prompt "Do you want to install $module? yes/no/all/none"
             , (-t STDIN ? 'y' : 'n');

    $install = $default_install_answer = 'y'
        if $install =~ m/^a/i;

    $install = $default_install_answer = 'n'
        if $install =~ m/^non/i;

    next if $install !~ m/^y/i;

    my $distr = $args{distr} || $module;

    $prereq{$distr} = $version;
    print "     Added $distr version $version to the requirements\n";
}

my $tests = $ENV{MAILBOX_RUN_TESTS}
 || prompt "Do you want to run the (large set of) tests? yes/no", "yes";

if($tests =~ m/n/i)
{   open F, ">", "skiptests";
    close F;
}
else
{   unlink "skiptests";
}

print <<'MAKEFILE';

**** Writing Makefile

MAKEFILE

WriteMakefile
 ( NAME       => 'Mail::Box'
 , VERSION    => $VERSION
 , AUTHOR     => 'Mark Overmeer'
 , ABSTRACT   => 'E-mail handling'
 , PREREQ_PM  => \%prereq
 , LICENSE    => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/mailbox/raw
DISTDIR         = ../public_html/mailbox/source

LICENSE         = artistic
EXTENDS		= ../UserIdentity:../MimeTypes:../ORL:../MailTools2:../MailBoxC

# for POD
FIRST_YEAR      = 2001
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/mailbox/

# for HTML
HTML_OUTPUT     = ../public_html/mailbox/html
HTML_DOCROOT    = /mailbox/html
HTML_PACKAGE    = ../public_html/mailbox/htmlpkg

__POSTAMBLE

print <<'DONE';

**** Done

DONE
