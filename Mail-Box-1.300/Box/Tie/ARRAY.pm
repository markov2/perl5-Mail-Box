
use strict;
package Mail::Box::Tie::ARRAY;
use Carp;

=head1 NAME

Mail::Box::Tie::ARRAY - Acces an existing message-folder as array

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

Read L<Mail::Box::Manager> first.

Folders certainly look like an array of messages, so why not just
access them as one?

Not all operations on arrays are supported.  Actually, most functions which
would reduce the size of the array are modified to signal messages as
ready for removal.

Examples what you I<cannot> do:

   shift/unshift/pop/splice @inbox;

=head1 METHODS for tied array

=over 4

=cut

#-------------------------------------------

=item tie ARRAY, 'Mail::Box::Tie::ARRAY', FOLDER

=item tie ARRAY, 'Mail::Box::Tie', FOLDER

Create the tie on an existing folder.  The second version is deprecated, but
will work because C<Mail::Box::Tie::TIEARRAY> will trigger this class.

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

Get the message which is on the indicated location in the list of
messages contained in this folder.  Deleted message will count.

Example:

   print $inbox[3];

=cut

sub FETCH($) { shift->{MBT_folder}->message(shift) }

#-------------------------------------------

=item STORE INDEX, MESSAGE

It is not permitted to randomly replace messages: it would disturb
threads etc.  The only thing what is allowed is to store a message
on the first free index behind the folder (which is also achievable
with PUSH -see below).

If you want to replace one message is a folder, then do the following:

    $inbox[3]->delete;
    push @inbox, $replacement;

=cut

sub STORE($$)
{   my ($self, $key, $msg) = @_;
    my $folder = $self->{MBT_folder};

    croak "Cannot simply replace messages in a folder: use delete old, then push new."
        if $key!=$folder->allMessages;

    $folder->addMessages($msg);
    $msg;
}

#-------------------------------------------

=item FETCHSIZE

Return the total number of messages in a folder.  This is called when
the folder-array is used in scalar context, for instance

    if(@inbox > 10)    # contains more than 10 messages
    my $nrmsgs = @inbox;

=cut

sub FETCHSIZE()  { scalar shift->{MBT_folder}->allMessages }

#-------------------------------------------

=item PUSH [MESSAGES]

Add messages to the (end of the) folder.

    push @inbox, $newmsg;

=cut

sub PUSH(@)
{   my $folder = shift->{MBT_folder};
    $folder->addMessages(@_);
    scalar $folder->allMessages;
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

# DESTROY is implemented in Mail::Box
#-------------------------------------------

=back

=head2 LIMITATIONS for arrays

This module implements C<TIEARRAY>, C<FETCH>, C<STORE>, C<FETCHSIZE>,
C<DELETE>, C<PUSH>, and C<DESTROY>.

This module does not implement all other methods as described in
the L<Tie::Array> manual-page.

=cut

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.300

=cut

1;
