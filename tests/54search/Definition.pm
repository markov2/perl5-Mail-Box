
package MailBox::Test::54search::Definition;

sub name     {"Mail::Box::Search; searching folders"}
sub critical {0}
sub skip     { undef }

my $sa_exists;

sub requires
{   my $class = shift;

    ( { package => 'Mail::SpamAssassin'
      , version => '2.00'
      , module  => undef   #same name
      , present => \$sa_exists

      , reason  => <<'REASON'
Searching for spam in a mail folder needs the popular spam killer.
BE WARNED: This module is large: installing will take quite a while. You
           can install it later.  When your CPAN cache is small, this may
           break your Mail::Box installing process.
REASON
      }
    )
}

1;
