
package MailBox::Test::81bodyconv::Definition;

sub name     {"Mail::Message::Convert; body type conversions"}
sub critical {0}
sub skip     { undef }

my $html_tree_exists;
my $html_format_exists;

sub requires
{   my $class = shift;

    ( { package => 'HTML::TreeBuilder'
      , version => '3.13'
      , module  => 'HTML::Tree'
      , present => \$html_tree_exists

      , reason  => <<'REASON'
The tree builder is used by the HTML::Format* packages.  Version 3.12 is
wrong, so you should install a newer version if you want smart html
conversions.
REASON
      }

    , { package => 'HTML::FormatText'
      , version => '2.01'
      , module  => 'HTML::Format'
      , present => \$html_format_exists

      , reason  => <<'REASON'
Plug-in which converts HTML to Postscript or plain text.
REASON
     }
   )
}

1;
