
use strict;
package Mail::Box::Tie;
use Carp;

=head1 NAME

Mail::Box::Tie - Acces an existing message-folder as array or hash

=head1 SYNOPSIS

As array:

   use Mail::Box::Tie;
   tie my(@inbox), 'Mail::Box::Tie::ARRAY', $folder;
   tie my(@inbox), 'Mail::Box::Tie', $folder; # depricated
   print $inbox[3];

or as hash:

   tie my(%inbox), 'Mail::Box::Tie::HASH', $folder;
   tie my(%inbox), 'Mail::Box::Tie', $folder; # depricated
   print $inbox{'<12379.124879@example.com>'};
 
=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.  The use of C<Mail::Box::Tie> is
depricated, and replaced by two seperate modules.  However, this
module still works.

Folders certainly look like an array of messages, so why not just
access them as one?  Or, the order is not important, but the
message-ids are (give relations): why not access them from a hash
based on this message-id?  Programs using one of these ties will
look simpler than programs using the more traditional method-calls.

See C<Mail::Box::Tie::ARRAY> and C<Mail::Box::Tie::HASH>

#-------------------------------------------

sub TIEHASH(@)
{   my $class = shift . "::HASH";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEHASH(@_);
}

sub TIEARRAY(@)
{   my $class = shift . "::ARRAY";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEARRAY(@_);
}

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.321

=cut

1;
