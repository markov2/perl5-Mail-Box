
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
searching for spam in a mail folder needs the popular Spam Assassin
module.  BE WARNED: This module is large: installing will take quite
a while.
REASON
      }
    )
}

1;
