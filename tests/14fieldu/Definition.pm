
package MailBox::Test::14fieldu::Definition;

sub name     {"Mail::Message::Field::Full; unicode fields"}
sub critical {0}

sub skip
{
   return "Requires module Encode, which requires at least Perl 5.7.3"
       if $] < 5.007003;

   eval "require Encode";
   return "Module Encode is not installed or has errors." if $@;

   undef;
}

1;
