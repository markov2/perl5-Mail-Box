
package MailBox::Test::54search::Definition;

sub name     {"Mail::Box::Search; searching folders"}
sub critical {0}
sub skip
{   eval "require Mail::SpamAssasssin";
    return "Mail::SpamAssassin is not installed or gives errors."
       if $@;
    undef;
}

1;
