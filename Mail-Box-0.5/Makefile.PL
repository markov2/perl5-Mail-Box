use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME	 => 'Mail::Box',
    VERSION_FROM => 'Box.pm', # finds $VERSION
    PREREQ_PM    => { Mail::Internet => 1.33
                    , MIME::Tools    => 5.406
                    }
);
