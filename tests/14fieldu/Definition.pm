
package MailBox::Test::14fieldu::Definition;

sub name     {"Mail::Message::Field::Full; unicode fields"}
sub critical {0}

my $nc_exists = 0;

sub requires
{   my $class = shift;

    ( { package => 'Encode'
      , version => '1.86'
      , module  => undef   #same name
      , present => \$enc_exists

      , reason  => <<'REASON'
Unicode conversions are done by this package.  It is a huge package,
but not complicated to install.  Many other Perl modules use it as well.
You may decide to install it later, with no need to reinstall Mail::Box.
REASON
      }
    )
}


sub skip
{
     $] < 5.007003
   ? "Requires module Encode, which requires at least Perl 5.7.3"
   : undef;
}

1;
