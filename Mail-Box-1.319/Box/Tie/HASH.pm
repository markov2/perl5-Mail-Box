
use strict;
package Mail::Box::Tie::HASH;
use Carp;

=head1 NAME

Mail::Box::Tie::HASH - Acces an existing message-folder as a hash

=head1 SYNOPSIS

   tie my(%inbox), 'Mail::Box::Tie', $folder;

   foreach my $msgid (keys %inbox)
   {   print $inbox{$msgid};
       delete $inbox{$msgid};
   }

   $inbox{$msg->messageID} = $msg;
   
=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.

Certainly when you look at a folder as being a set of related messages,
based on message-id, folder-access through a hash is a logical step.

For a tied-hash, the message-id is used as key.  The message-id is usually
unique, but when two or more instances of the same message are in the
same folder, one will be flagged for deletion and the other will show.

This implementation uses basic folder-access routines which are related
to the message-id.

=head1 METHODS

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

sub FETCH($) { shift->{MBT_folder}->messageID(shift) }

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

sub STORE($$)
{   my ($self, $key, $msg) = @_;
    my $folder = $self->{MBT_folder};
    $folder->coerce($msg);
    my $mid = $msg->messageID;
    $key    = $mid if $key eq 'undef' || !$key;

    croak "Tried to store message with $mid in hash under $key"
       if $mid && $mid ne $key;

    $folder->addMessages($msg);
    $msg;
}

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

sub DELETE($) { shift->{MBT_folder}->messageID(shift)->delete }

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

This code is beta, version 1.3.19

=cut

1;
