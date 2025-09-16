use ExtUtils::MakeMaker;

require 5.016;

use warnings;
use strict;


# Use command 'oodist' to produce your whole software release.
my $version = '3.012';
my $webpages = "../public_html";
my $git      = "https://github.com/markov2/perl5-Mail-Box";
my $publish  = "../public_html/mail-box";
my $homepage = "http://perl.overmeer.net/CPAN/";

my %oodist   = (
	oodoc_version => 3.05,
	first_year    => 2001,
	email         => "markov\@cpan.org",

	include  => [
		'../HTML-FromMail',
 		'../MIME-Types',
 		'../Mail-Box-IMAP4',
 		'../Mail-Box-POP3',
 		'../Mail-Box-Parser-C',
 		'../Mail-Message',
 		'../Mail-Transport',
 		'../MailTools',
 		'../Object-Realize-Later',
 		'../User-Identity',
 		'/p/MailDbx',
	],

	use      => [
	],

	parser   => {
		syntax         => 'markov',
		skip_links     => [
		],
		pmhead         => undef,
	},

	tests    => {
	},

	release  => {
		publish        => "$publish/source",
	},

	raw      => {
		publish        => "$publish/raw",
	},

	generate => [
	  {
		# Add real pod to the releases
		format         => 'pod3',
		podtail        => undef,
	  },
 	  {	format         => 'html',
		webpages       => "$webpages/mailbox/html",
		publish        => "$publish/htmlpkg",
		docroot        => "/mailbox/html",
		templates      => "html",
		stylesheet     => "/oodoc.css",
	  },
 		  # You may add exporter configurations here.
	],
);


my %prereq = (
	'Carp'           => 0,
	'Cwd'            => 0,
	'Date::Parse'    => 0,
	'Devel::GlobalDestruction' => 0.09,
	'Errno'          => 0,
	'Fcntl'          => 0,
	'File::Basename' => 0,
	'File::Spec'     => 0.7,
	'File::Compare'  => 0,
	'File::Copy'     => 0,
	'File::Remove'   => 0.20,
	'File::Temp'     => 0,
	'IO::Scalar'     => 0,
	'Mail::Message'  => 3.013,
	'Mail::Transport' => 3.003,
	'Object::Realize::Later' => 0.19,
	'POSIX'          => 0,
	'Scalar::Util'   => 1.13,
	'Sys::Hostname'  => 0.0,
	'Test::More'     => 0.47,

# Currently, it seems to be wise not to depend on these
#   Mail::SpamAssassin    split-off?
#   File::FcntLock
);


WriteMakefile
	NAME       => 'Mail::Box',
	VERSION    => $version,
	AUTHOR     => 'Mark Overmeer',
	ABSTRACT   => 'complete E-mail handling suite',
	PREREQ_PM  => \%prereq,
	LICENSE    => 'perl_5',

	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources   => {
			repository => {
				type => 'git',
				url  => "$git.git",
				web  => $git,
			},
			homepage => $homepage,
			license  => [ 'http//dev.perl.org/licenses/' ],
		},
		prereqs => {
			develop => {
				requires => {
					'OODoc' => '3.00',
				}
			},
			test => {
				requires => {
					'Test::More' => 1.00,
					'Test::Pod'  => 1.00,
				}
			},
		},

		# You may use multiple set-ups, see "oodist --make"
		x_oodist => \%oodist,
	};
