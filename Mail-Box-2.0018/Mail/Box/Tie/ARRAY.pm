
use strict;
package Mail::Box::Tie::ARRAY;

our $VERSION = 2.00_18;

use Carp;

=head1 NAME

Mail::Box::Tie::ARRAY - Access an existing message folder as array

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open(folder => 'inbox');

 use Mail::Box::Tie::ARRAY;
 tie my(@inbox), 'Mail::Box::Tie::ARRAY', $folder;

 # deprecated, but works too
 use Mail::Box::Tie;
 tie my(@inbox), 'Mail::Box::Tie', $folder;

 foreach (@inbox) {print $_->short}
 print $_->print foreach @inbox;
 my $emails = @inbox;

 print $inbox[3];
 print scalar @inbox;
 push @inbox, Mail::Box::Message->new(...);
 delete $inbox[6];
 print $inbox[0]->head->get('status');

 my $folder = tied @inbox;
 untie @inbox;
   
=head1 DESCRIPTION

Certainly when you look at a folder as a list of messages, it is logical to
access the folder through an array.

Not all operations on arrays are supported.  Actually, most functions which
would reduce the size of the array are modified instead to mark messages for
deletion.

Examples what you I<cannot> do:

   shift/unshift/pop/splice @inbox;

=head1 METHOD INDEX

The general methods for C<Mail::Box::Tie::ARRAY> objects:

      DELETE                               PUSH [MESSAGES]
      FETCH INDEX                          STORE INDEX, MESSAGE
      FETCHSIZE                            STORESIZE LENGTH

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item tie ARRAY, 'Mail::Box::Tie::ARRAY', FOLDER

=item tie ARRAY, 'Mail::Box::Tie', FOLDER

Create the tie on an existing folder.  The second version is deprecated, but
will work because C<Mail::Box::Tie::TIEARRAY> will trigger usage of this
class.

Example:

    my $mgr   = Mail::Box::Manager->new;
    my $inbox = $mgr->new(folder => $ENV{MAIL});
    tie my(@inbox), ref $inbox, $inbox;

=cut

sub TIEARRAY(@)
{   my ($class, $folder) = @_;
    croak "No folder specified to tie to."
        unless ref $folder && $folder->isa('Mail::Box');

    bless { MBT_folder => $folder }, $class;
}

#-------------------------------------------

=item FETCH INDEX

Get the message which is at the indicated location in the list of
messages contained in this folder.  Deleted messages will be counted.

Example:

   print $inbox[3];

=cut

sub FETCH($) { shift->{MBT_folder}->message(shift) }

#-------------------------------------------

=item STORE INDEX, MESSAGE

Random message replacement is is not permitted--doing so would disturb threads
etc.  An error occurs if you try to do this. The only thing which is allowed
is to store a message at the first free index at the end of the folder (which
is also achievable with PUSH--see below).

If you want to replace one message in a folder, then do the following:

    $inbox[3]->delete;
    push @inbox, $replacement;

=cut

sub STORE($$)
{   my ($self, $index, $msg) = @_;
    my $folder = $self->{MBT_folder};

    croak "Cannot simply replace messages in a folder: use delete old, then push new."
        if $index != $folder->messages;

    $folder->addMessages($msg);
    $msg;
}

#-------------------------------------------

=item FETCHSIZE

Return the total number of messages in a folder.  This is called when
the folder-array is used in scalar context, for instance.

    if(@inbox > 10)    # contains more than 10 messages
    my $nrmsgs = @inbox;

=cut

sub FETCHSIZE()  { scalar shift->{MBT_folder}->messages }

#-------------------------------------------

=item PUSH [MESSAGES]

Add messages to the end of the folder.

    push @inbox, $newmsg;

=cut

sub PUSH(@)
{   my $folder = shift->{MBT_folder};
    $folder->addMessages(@_);
    scalar $folder->messages;
}
 

#-------------------------------------------

=item DELETE

Flag a message to be removed.  Be warned that the message stays in
the folder, and is not removed before the folder is written.

Examples:

 delete $inbox[5];
 $inbox[5]->delete;   #same

=cut

sub DELETE($) { shift->{MBT_folder}->message(shift)->delete }

#-------------------------------------------

=item STORESIZE LENGTH

Sets all messages behind from LENGTH to the end of folder to be deleted.

=cut

sub STORESIZE($)
{   my $folder = shift->{MBT_folder};
    my $length = shift;
    $folder->message($_) foreach $length..$folder->messages;
    $length;
}

# DESTROY is implemented in Mail::Box
#-------------------------------------------

=back

=head2 LIMITATIONS for arrays

This module implements C<TIEARRAY>, C<FETCH>, C<STORE>, C<FETCHSIZE>,
C<STORESIZE>, C<DELETE>, C<PUSH>, and C<DESTROY>.

This module does not implement all other methods as described in
the L<Tie::Array> documentation, because the real array of messages
is not permitted to shrink or be mutulated.

=cut

#-------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
