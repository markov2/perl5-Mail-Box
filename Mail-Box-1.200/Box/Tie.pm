
use strict;
package Mail::Box::Tie;
use Carp;

=head1 NAME

Mail::Box::Tie - Acces an existing message-folder as array or hash

=head1 SYNOPSIS

As array:

   use Mail::Box::Tie;
   tie my(@inbox), 'Mail::Box::Tie', $folder;

   foreach (@inbox) {print $_->short}
   print $inbox[3];
   push @inbox, Mail::Box::Message->new(...);
   my $folder = tied @inbox;

or as hash:

   tie my(%inbox), 'Mail::Box::Tie', $folder;

   foreach my $msgid (keys %inbox)
   {   print $inbox{$msgid};
       delete $inbox{$msgid};
   }

   $inbox{$msg->messageID} = $msg;
   
=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.

Folders certainly look like an array of messages, so why not just
access them as one?  Or, the order is not important, but the
message-ids are (give relations): why not access them from a hash
based on this message-id?  Programs using one of these ties will
look simpler than programs using the more traditional method-calls.

A full example:

    use Mail::Box::Manager;
    use Mail::Box::Tie;

    my $mgr    = Mail::Box::Manager->new;
    my $folder = $mgr->open(folder => 'inbox');
    tie my(@inbox), 'Mail::Box::Tie', $folder;

    print scalar @inbox, " messages.\n";
    print $_->print foreach @inbox;

    untie @inbox;      # force destroy tie

=head1 TIE-ING ARRAYS

Access the folder as if it is an array of messages (of course, there
is much more involved like reading, writing, and locking).

=head2 DESCRIPTION for tied array

Not all operations on arrays are supported.  Actually, most functions which
would reduce the size of the array are modified to signal messages as
ready for removal.

Examples of what you I<can> do:

   tie my(@inbox), 'Mail::Box::Tie', ...;

   my $message = new Mail::Box::Message(...);
   push @inbox, $message;
   delete $inbox[2];         # performed when folder is written
   $inbox[3]   = $message;
   print $inbox[0]->head->get('status');
   my $emails  = @inbox;
   untie @inbox;             # calls write()

   # Direct access to the Mail::Box object.
   my $folder = tied @inbox;
   $folder->write;

Examples what you I<cannot> do:

   shift/unshift/pop/splice @inbox;

=head1 METHODS for tied array

=over 4

=cut

#-------------------------------------------

=item tie ARRAY, 'Mail::Box::Tie', FOLDER

Create the tie on an existing folder.

Example:

    my $mgr   = Mail::Box::Manager->new;
    my $inbox = $mgr->new(folder => $ENV{MAIL});
    tie my(@inbox), ref $inbox, $inbox;

=cut

sub TIEARRAY(@)
{   my ($class, $folder) = @_;
    croak "No folder specified to tie to."
        unless ref $folder && $folder->isa('Mail::Box');

    bless { MBT_folder => $folder, MBT_type => 'ARRAY' }, $class;
}

#-------------------------------------------

=item FETCH INDEX

Get the message which is on the indicated location in the list of
messages contained in this folder.  Deleted message will count.

Example:

   print $inbox[3];

=cut

sub FETCH($)
{   my $folder = shift->{MBT_folder};
    my $key    = shift;

    $key =~ /\D/
    ? $folder->messageID($key)    # as hash (msgid are never only digits)
    : $folder->message($key);     # as array
}

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

    if($self->{MBT_type} eq 'HASH')
    {   # tied to hash.
        $folder->coerce($msg);
        my $mid = $msg->messageID;
        $key    = $mid if $key eq 'undef' || !$key;

        croak "Tried to store message with $mid in hash under $key"
           if $mid && $mid ne $key;
    }
    else
    {   # tied to array.
        croak "Cannot simply replace messages in a folder: use delete old, then push new."
            if $key!=$folder->allMessages;
    }

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

=head1 TIE-ING HASHES

For a tied-hash, the message-id is used as key.  The message-id is usually
unique, but when two or more instances of the same message are in the
same folder, one will be flagged for deletion and the other will show.

This implementation uses basic folder-access routines which are related
to the message-id.

=head2 DESCRIPTION for tied hash

=head2 METHODS for tied hash

=over 4

=back

#-------------------------------------------

=item TIEHASH FOLDERTYPE, INIT-PARAMETERS

=item TIEHASH 'Mail::Box::Tie', FOLDER

Connects the object to a hash.

Examples:

    my $mgr    = Mail::Box::Manager->new;
    my $folder = $mgr->open(access => 'rw');
    tie my(%inbox), 'Mail::Box::Tie', $folder;

=cut

sub TIEHASH(@)
{   my ($class, $folder) = @_;
    croak "No folder specified to tie to."
        unless ref $folder && $folder->isa('Mail::Box');

    bless { MBT_folder => $folder, MBT_type => 'HASH' }, $class;
}

#-------------------------------------------

=item FETCH MESSAGEID

Get the message with the specified id.  The returned message may be
a dummy, when message-thread detection is used.  Returns undef when
no message with the specified id is known.

Examples:

    my $msg = $inbox{$msgid};
    if($inbox{$msgid}->isDummy)  ...

=cut

# Implemented above

#-------------------------------------------

=item STORE MESSAGEID, MESSAGE

Store a message in the hash, on the specified id.  The message-id must
be equivalent the message-id as contained in the message.

If the message does not have a message-id assigned yet, it will get
the specified one.  When message-id is undef, the key will be taken
from the message.

Examples:

    $inbox{$msg->messageID} = $msg;
    $inbox{undef} = $msg;

=cut

# implemented above

#-------------------------------------------

=item FIRSTKEY

=item NEXTKEY

Returns the first respecitively sequential pair of message-id/message
from the folder.  The messages will be returned in the order as stored
in the folder.  Messages flagged for deletion WILL be taken.

Examples:

    foreach my $msgid (keys %inbox) ...
    foreach my $msg (values %inbox) ...

    while(my ($msgid, $msg) = each %inbox) {
        $msg->print unless $msg->deleted;
    }

=cut

sub FIRSTKEY()
{   my $self   = shift;
    my $folder = $self->{MBT_folder};

    $self->{MBT_each_index} = 0;
    return undef unless $folder->allMessages;

    my $msg    = $folder->message(0);
    $msg->messageID;
}

sub NEXTKEY($)
{   my $self   = shift;
    my $folder = $self->{MBT_folder};
    my $index  = ++($self->{MBT_each_index});
    return undef if $index >= $folder->allMessages;

    my $msg    = $folder->message($index);
    $msg->messageID;
}

#-------------------------------------------

=item EXISTS MESSAGE-ID

Check whether a message with a certain MESSAGE-ID exists.

Example:

    if(exists $inbox{$msgid}) ...

=cut

sub EXISTS($)
{   my $folder = shift->{MBT_folder};
    my $msgid  = shift;
    defined $folder->messageID($msgid);
}

#-------------------------------------------

=item DELETE MESSAGE-ID

Remove the message with the specified MESSAGE-ID.

Example:

    delete $inbox{$msgid};

=cut

# Already implemented above as delete on an array element.

#-------------------------------------------

=item CLEAR

Remove the contents of the hash.  Not really possible, but all
the messages will be set to be deleted.

Example:

   %inbox = ();
   %inbox = ($msg->messageID, $msg); #before adding msg

=cut

sub CLEAR()
{   my $folder = shift->{MBT_folder};
    $_->delete foreach $folder->messages;
}

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.200

=cut

1;
