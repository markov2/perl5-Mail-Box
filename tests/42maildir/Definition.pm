
package MailBox::Test::42maildir::Definition;

sub name     {"Mail::Box::Maildir; maildir folders"}
sub critical {0}
sub requires { () }

sub skip()
{
      $^O =~ m/mswin/i
    ? 'Maildir filenames are not compatible with Windows'
    : undef;
}

1;
