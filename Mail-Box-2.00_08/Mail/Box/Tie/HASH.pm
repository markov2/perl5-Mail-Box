
use strict;
package Mail::Box::Tie::HASH;

our $VERSION = 2.00_08;

use Carp;

=head1 NAME

 Mail::Box::Tie::HASH - Access an existing message folder as a hash

=head1 SYNOPSIS

 tie my(%inbox), 'Mail::Box::Tie', $folder;

 foreach my $msgid (keys %inbox)
 {   print $inbox{$msgid};
     delete $inbox{$msgid};
 }

 $inbox{$msg->messageId} = $msg;
   
=head1 DESCRIPTION

Certainly when you look at a folder as being a set of related messages
based on message-id, it is logical to access the folder through a hash.

For a tied hash, the message-id is used as the key.  The message-id is usually
unique, but when two or more instances of the same message are in the same
folder, one will be flagged for deletion and the other will be returned.

This implementation uses basic folder access routines which are related
to the message-id.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Tie::HASH> objects:

 

=head1 METHODS

=over 4

=back

#-------------------------------------------

=item TIEHASH FOLDERTYPE, INIT-PARAMETERS

=item TIEHASH 'Mail::Box::Tie', FOLDER

Connects the folder object to a hash.

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
a dummy if message thread detection is used.  Returns C<undef> when
there is no message with the specified id.

Examples:

    my $msg = $inbox{$msgid};
    if($inbox{$msgid}->isDummy)  ...

=cut

sub FETCH($) { shift->{MBT_folder}->messageId(shift) }

#-------------------------------------------

=item STORE MESSAGEID, MESSAGE

Store a message in the hash using the specified id.  The message-id must be
the same as the message-id contained in the message.  If the message does not
have a message-id yet, it will get the specified one.  When message-id is
C<undef>, the key will be taken from the message.

Examples:

    $inbox{$msg->messageId} = $msg;
    $inbox{undef} = $msg;

=cut

sub STORE($$)
{   my ($self, $key, $msg) = @_;
    my $folder = $self->{MBT_folder};
    $folder->coerce($msg);
    my $mid = $msg->messageId;
    $key    = $mid if $key eq 'undef' || ! defined $key;

    croak "Tried to store message with message-id $mid in hash using " .
         "message-id key $key"
       if $mid && $mid ne $key;

    $folder->addMessages($msg);
    $msg;
}

#-------------------------------------------

=item FIRSTKEY

=item NEXTKEY

FIRSTKEY returns the first message-id/message pair from the folder, and
NEXTKEY returns the message-id/message pair for the next message, in the order
in which the message is stored in the folder. Messages flagged for deletion
B<WILL> be returned. See the C<allMessages> method of the folder type for more
information about the folder message order.

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
    $msg->messageId;
}

sub NEXTKEY($)
{   my $self   = shift;
    my $folder = $self->{MBT_folder};
    my $index  = ++($self->{MBT_each_index});
    return undef if $index >= $folder->allMessages;

    my $msg    = $folder->message($index);
    $msg->messageId;
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
    defined $folder->messageId($msgid);
}

#-------------------------------------------

=item DELETE MESSAGE-ID

Remove the message with the specified MESSAGE-ID.

Example:

    delete $inbox{$msgid};

=cut

sub DELETE($) { shift->{MBT_folder}->messageId(shift)->delete }

#-------------------------------------------

=item CLEAR

Remove the contents of the hash.  This is not really possible, but all
the messages will be flagged for deletion.

Example:

   %inbox = ();
   %inbox = ($msg->messageId, $msg); #before adding msg

=cut

sub CLEAR()
{   my $folder = shift->{MBT_folder};
    $_->delete foreach $folder->messages;
}

#-------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_08.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
