use ExtUtils::MakeMaker;

WriteMakefile
   ( NAME      => 'Mail::Box'
   , PMLIBDIRS => [ qw/Box Message Transport/ ]
   );
