
package Mail::Box::Tie;

use strict;
use v5.6.0;

our $VERSION = '0.1';

=head1 NAME

Mail::Box::Tie - Acces an existing message-folder as array

=head1 SYNOPSIS

   tie my @inbox, 'Mail::Box::File', file => $ENV{MAIL};
   tie my @inbox, $folder;

   foreach (@inbox) {print $_->short}
   print $inbox[3];
   push @inbox, Mail::Box::Message->new(...);
   my $folder = tied @inbox;

=head1 DESCRIPTION

Read Mail::Box::Manager first.
Folder certainly look as arrays, so why not just access them as one.  Each
folder is a sub-class of this class.

=head1 PUBLIC INTERFACE

Not all operations on arrays are supported.  Actually, most functions which
would reduce the size of the array are modified to signal messages as
ready for removal.

Examples of what you I<can> do:

   tie my @inbox, 'Mail::Box::File', ...;
   my $message = new Mail::Box::Message(...);

   push @inbox, $message;
   delete $inbox[2];         # becomes undef
   $inbox[3]   = $message;
   print $inbox[0]->status;
   my $emails  = @inbox;
   untie @inbox;             # calls write()

   # Direct access to the Mail::Box object.
   my $folder = tied @inbox;
   $folder->synchonize;

Examples what you I<cannot> do:

   shift/unshift/pop/splice @inbox;

=over 4

=cut

#-------------------------------------------

=item tie ARRAY, FOLDERTYPE, PARAMS

=item tie ARRAY, FOLDERTYPE, FOLDER

There are to ways to construct a tie.  In the first case, you start with
a tie, and may later ask for the tied folder structure.  In the second
version, you have first created a folder, and then put a tie around it.

The first version: tie an ARRAY to a folder of type FOLDERTYPE, where
the constructor of the folder requires some parameters.  Possible PARAMS
are the parameters of the C<new> constructor of the specified folder-type.

Example:
    tie my(@inbox), 'Mail::Box::File', folder => $ENV{MAIL};
    my $inbox = tied @inbox;

The second version: tie an ARRAY interface around an existing FOLDER.  The
type as specified with FOLDERTYPE is only used to find the correct
TIEARRAY method, usually the result of C<ref FOLDER>.

Example:
    my $inbox = Mail::Box::File->new(folder => $ENV{MAIL});
    tie my(@inbox), ref $inbox, $inbox;

=cut

sub TIEARRAY(@)
{   my $class = shift;
    return shift if ref $_[0] && $_[0]->isa('Mail::Box');
    $class->new(@_);
}

sub FETCH($)     { shift->activeMessage(@_) }

sub STORE($$)
{   my Mail::Box $self = shift;
    my $index = shift;
    $self->activeMessage($index) = shift;
}

sub FETCHSIZE()  { scalar shift->messages }

sub PUSH(@)
{   my Mail::Box $self = shift;
    $self->addMessages(@_);
    scalar $self->messages;
}
 
sub DELETE($) { shift->activeMessage(shift)->delete }

# DESTROY is implemented in Mail::Box
#-------------------------------------------

=back

=head2 IMPLEMENTED METHODS

This module implements C<TIEARRAY>, C<FETCH>, C<STORE>, C<FETCHSIZE>,
C<DELETE>, C<PUSH>, and C<DESTROY>.

This module does not implement all other methods as described in
the L<Tie::Array> manual-page.

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.3

=cut

1;
