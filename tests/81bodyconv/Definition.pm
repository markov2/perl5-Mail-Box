
package MailBox::Test::81bodyconv::Definition;

sub name     {"Mail::Message::Convert; body type conversions"}
sub critical {0}
sub skip()   {undef}  # try even when some modules are not installed.

1;
