
package MailBox::Test::80msgconv::Definition;

sub name     {"Mail::Message::Convert; message conversions"}
sub critical {0}

my $mi_exists;
my $me_exists;

sub requires
{   my $class = shift;

    ( { package => 'Mail::Internet'
      , version => '1.0'
      , module  => 'MailTools'
      , present => \$mi_exists

      , reason  => <<'REASON'
Many existing e-mail applications use Mail::Internet objects.  If
you want automatic conversions for compatibility, you need this.
REASON
      }
 
    , { package => 'MIME::Entity'
      , version => '3.0'
      , module  => 'MIME::Tools'
      , present => \$me_exists

      , reason  => <<'REASON'
MIME::Entity extends Mail::Internet messages with multipart handling
and composition.  Install this when you want compatibility with
modules which are based on this kind of messages.
REASON
      }
    );
}

sub skip     { undef }

1;
