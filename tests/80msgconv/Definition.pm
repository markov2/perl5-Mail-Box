
package MailBox::Test::80msgconv::Definition;

sub name     {"Mail::Message::Convert; message conversions"}
sub critical {0}

sub skip
{   eval "require Mail::Internet";
    my $mailtools = !$@;

    eval "require MIME::Entity";
    my $mime = !$@;

    return "Neighter MailTools nor MIME::Tools are installed"
       unless $mailtools || $mime;

    undef;
}

1;
