
use strict;
package Mail::Box::Tie::ARRAY;

use Carp;

=head1 NAME

Mail::Box::Tie::ARRAY - access an existing message folder as array

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

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method tie ARRAY, 'Mail::Box::Tie::ARRAY', FOLDER

Create the tie on an existing folder.

=examples

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

=head2 Tied Interface

=cut

#-------------------------------------------

=method FETCH INDEX

Get the message which is at the indicated location in the list of
messages contained in this folder.  Deleted messages will be returned
as C<undef>

=example

 print $inbox[3];

=cut

sub FETCH($)
{   my ($self, $index) = @_;
    my $msg = $self->{MBT_folder}->message($index);
    $msg->deleted ? undef : $msg;
}

#-------------------------------------------

=method STORE INDEX, MESSAGE

Random message replacement is is not permitted--doing so would disturb threads
etc.  An error occurs if you try to do this. The only thing which is allowed
is to store a message at the first free index at the end of the folder (which
is also achievable with PUSH--see below).

=examples

 $inbox[$#inbox] = $add;
 push @inbox, $add;

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

=method FETCHSIZE

Return the total number of messages in a folder.  This is called when
the folder-array is used in scalar context, for instance.

=examples

 if(@inbox > 10)    # contains more than 10 messages?
 my $nrmsgs = @inbox;

=cut

sub FETCHSIZE()  { scalar shift->{MBT_folder}->messages }

#-------------------------------------------

=method PUSH MESSAGES

Add MESSAGES to the end of the folder.

=example

    push @inbox, $newmsg;

=cut

sub PUSH(@)
{   my $folder = shift->{MBT_folder};
    $folder->addMessages(@_);
    scalar $folder->messages;
}
 

#-------------------------------------------

=method DELETE

Flag a message to be removed.  Be warned that the message stays in
the folder, and is not removed before the folder is written.

=examples

 delete $inbox[5];
 $inbox[5]->delete;   #same

=cut

sub DELETE($) { shift->{MBT_folder}->message(shift)->delete }

#-------------------------------------------

=method STORESIZE LENGTH

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

=head1 IMPLEMENTATION

This module implements C<TIEARRAY>, C<FETCH>, C<STORE>, C<FETCHSIZE>,
C<STORESIZE>, C<DELETE>, C<PUSH>, and C<DESTROY>.

This module does not implement all other methods as described in
the L<Tie::Array> documentation, because the real array of messages
is not permitted to shrink or be mutilated.

=cut

#-------------------------------------------

1;
