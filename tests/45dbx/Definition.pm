
package MailBox::Test::45dbx::Definition;

sub name     {"Mail::Box::Dbx; reading Outlook Express folders"}
sub critical {0}

my $dbx_exists;

sub requires
{   my $class = shift;

    ( { package => 'Mail::Transport::Dbx'
      , version => '0.04'
      , module  => undef
      , present => \$dbx_exists

      , reason  => <<'REASON'
The wrapper to the Outlook's dbx files consists of a c-library
named libdbx (website http://sorceforge.net/project/ol2mbox/),
and a wrapper which is distributed separately from Mail::Box.
You get read-only access to the the dbx folders.
REASON
      }
 
    );
}

sub skip     { undef }

1;
