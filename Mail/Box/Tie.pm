
package Mail::Box::Tie;

use strict;

use Carp;

=head1 NAME

Mail::Box::Tie - access an existing message-folder as an array or hash

=head1 SYNOPSIS

As an array:

 use Mail::Box::Tie;
 tie my(@inbox), Mail::Box::Tie::ARRAY => $folder;
 tie my(@inbox), Mail::Box::Tie => $folder;    # deprecated
 print $inbox[3];

or as hash:

 tie my(%inbox), Mail::Box::Tie::HASH => $folder;
 tie my(%inbox), Mail::Box::Tie => $folder;    # deprecated
 print $inbox{'<12379.124879@example.com>'};
 
=head1 DESCRIPTION

The use of Mail::Box::Tie is deprecated, because it is succeeded by two
separate modules: Mail::Box::Tie::ARRAY and Mail::Box::Tie::HASH.
However, this module still works.

Folders certainly look like an array of messages, so why not just
access them as one?  Or, the order is not important, but the
message-ids are (give relations): why not access them from a hash
based on this message-id?  Programs using one of these ties will
look simpler than programs using the more traditional method calls.

=head1 METHODS

=cut

#-------------------------------------------

sub TIEHASH(@)
{   my $class = (shift) . "::HASH";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEHASH(@_);
}

#-------------------------------------------

sub TIEARRAY(@)
{   my $class = (shift) . "::ARRAY";
    eval "require $class";   # bootstrap

    confess $@ if $@;
    $class->TIEARRAY(@_);
}

#-------------------------------------------

1;
