
package MailBox::Test::42maildir::Definition;

use Tools    qw/$windows/;

sub name     {"Mail::Box::Maildir; maildir folders"}
sub critical { 0 }
sub skip()
{
      $windows
    ? 'Maildir filenames are not compatible with Windows.'
    : undef;
}

1;
