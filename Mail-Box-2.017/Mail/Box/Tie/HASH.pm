
use strict;
package Mail::Box::Tie::HASH;

our $VERSION = 2.017;

use Carp;

=head1 NAME

Mail::Box::Tie::HASH - access an existing message folder as a hash

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

      CLEAR                                FIRSTKEY
      DELETE MESSAGE-ID                    NEXTKEY
      EXISTS MESSAGE-ID                    STORE undef, MESSAGE
      FETCH MESSAGEID                      TIEHASH ...

=head1 METHODS

=over 4

=cut

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

=item STORE undef, MESSAGE

Store a message in the folder.  The key must be C<undef>, because the
message-id of the specified message is taken.  This is shown in the
first example.  However, as you see, it is a bit complicated to specify
C<undef>, therefore the string C<"undef"> is accepted as weel.

The message may be converted into something which can be stored in the
folder type which is at stake.  The added instance is returned.

Example:

    $inbox{ (undef) } = $msg;
    $inbox{undef} = $msg;

=cut

sub STORE($$)
{   my ($self, $key, $basicmsg) = @_;

    carp "Use undef as key, because the message-id of the message is used."
        if defined $key && $key ne 'undef';

    $self->{MBT_folder}->addMessages($basicmsg);
}

#-------------------------------------------

=item FIRSTKEY

=item NEXTKEY

FIRSTKEY returns the first message-id/message pair from the folder, and
NEXTKEY returns the message-id/message pair for the next message, in the order
in which the message is stored in the folder. Messages flagged for deletion
B<WILL> be returned. See the C<messages> method of the folder type for more
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
    return undef unless $folder->messages;

    my $msg    = $folder->message(0);
    $msg->messageId;
}

sub NEXTKEY($)
{   my $self   = shift;
    my $folder = $self->{MBT_folder};
    my $index  = ++($self->{MBT_each_index});
    return undef if $index >= $folder->messages;

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

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
