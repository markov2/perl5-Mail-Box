use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME	 => 'Mail::Box',
    VERSION_FROM => 'Mail/Box.pm', # finds $VERSION
    DIR          => [ 'Mail' ],
    PREREQ_PM    => { Date::Parse    => 0.0
		    , File::Spec     => 0.7
                    , IO::Scalar     => 0.0
		    , Errno          => 0.0
		    , Scalar::Util   => 1.06
		    , Object::Realize::Later => 0.02
		    , Mail::Address  => 0.0
                    }
);
