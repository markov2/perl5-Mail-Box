#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Tie;

use strict;
use warnings;

use Carp;
use Scalar::Util   qw/blessed/;

#--------------------
=chapter NAME

Mail::Box::Tie - access an existing message-folder as an array or hash

=chapter SYNOPSIS

As an array:

  tie my(@inbox), Mail::Box::Tie::ARRAY => $folder;
  print $inbox[3];

or as hash:

  tie my(%inbox), Mail::Box::Tie::HASH => $folder;
  print $inbox{'<12379.124879@example.com>'};

=chapter DESCRIPTION

Folders certainly look like an array of messages, so why not just
access them as one?  Or, the order is not important, but the
message-ids are (give relations): why not access them from a hash
based on this message-id?  Programs using one of these ties will
look simpler than programs using the more traditional method calls.

=chapter METHODS

=section Constructors

=c_method new $folder, $type
Do not call this method directly, but via the tie interface.
=cut

sub new($$)
{	my ($class, $folder, $type) = @_;

	blessed $folder && $folder->isa('Mail::Box')
        or croak "No folder specified to tie to.";

	bless +{ MBT_folder => $folder, MBT_type => $type }, $class;
}

#--------------------
=section Attributes

=method folder
=method type
=cut

sub folder() { $_[0]->{MBT_folder} }
sub type()   { $_[0]->{MBT_type} }

1;
