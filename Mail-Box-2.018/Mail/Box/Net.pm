
use strict;
package Mail::Box::Net;

use base 'Mail::Box';
our $VERSION = 2.018;

use Mail::Box::Net::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;
use Mail::Message::Head::Delayed;

use Carp;
use FileHandle;
use File::Copy;
use File::Spec;
use File::Basename;

=head1 NAME

Mail::Box::Net - handle folders which are stored remote.

=head1 CLASS HIERARCHY

 Mail::Box::Net
 is a Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 # Do not instantiate this object yourself

=head1 DESCRIPTION

This documentation describes how directory organized mailboxes work.
Please read C<Mail::Box-Overview> first.

At the moment, this object is extended by

=over 4

=item * MH

=item * Maildir

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Box> (MB), L<Mail::Reporter> (MR).

The general methods for C<Mail::Box::Net> objects:

   MB addMessage  MESSAGE               MB messageId MESSAGE-ID [,MESS...
   MB addMessages MESSAGE [, MESS...    MB messageIds
   MB close OPTIONS                     MB messages ['ALL',RANGE,'ACTI...
   MB copyTo FOLDER, OPTIONS            MB modified [BOOLEAN]
   MB create FOLDERNAME [, OPTIONS]     MB name
   MB current [NUMBER|MESSAGE|MES...       new OPTIONS
   MB delete                            MB openSubFolder NAME [,OPTIONS]
   MR errors                            MR report [LEVEL]
   MB find MESSAGE-ID                   MR reportAll [LEVEL]
   MB listSubFolders OPTIONS            MR trace [LEVEL]
   MB locker                            MR warnings
   MR log [LEVEL [,STRINGS]]            MB writable
   MB message INDEX [,MESSAGE]

The extra methods for extension writers:

   MR AUTOLOAD                          MB organization
   MB DESTROY                           MB read OPTIONS
   MB appendMessages OPTIONS            MB readMessages OPTIONS
   MB clone OPTIONS                     MB scanForMessages MESSAGE, ME...
   MB coerce MESSAGE                    MB sort PREPARE, COMPARE, LIST
   MB determineBodyType MESSAGE, ...    MB storeMessage MESSAGE
   MB folderdir [DIR]                   MB timespan2seconds TIME
   MB foundIn [FOLDERNAME], OPTIONS     MB toBeThreaded MESSAGES
   MR inGlobalDestruction               MB toBeUnthreaded MESSAGES
   MB lineSeparator [STRING|'CR'|...    MB update OPTIONS
   MR logPriority LEVEL                 MB updateMessages OPTIONS
   MR logSettings                       MB write OPTIONS
   MR notImplemented                    MB writeMessages
   MB openRelatedFolder OPTIONS

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new folder.  The are many options which are taken from other
objects.  For some, different options are set.  For MH-specific options
see below, but first the full list.

 OPTION            DEFINED BY         DEFAULT
 access            Mail::Box          'r'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          undef
 head_wrap         Mail::Box          72
 keep_dups         Mail::Box          0
 extract           Mail::Box          10kB
 lock_type         Mail::Box          'DOTLOCK'
 lock_file         Mail::Box          foldername.'/.lock'
 lock_timeout      Mail::Box          3600    (1 hour)
 lock_wait         Mail::Box          10      (seconds)
 log               Mail::Reporter     'WARNINGS'
 password          Mail::Box::Net     undef
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 server_name       Mail::Box::Net     undef
 server_port       Mail::Box::Net     undef
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Box          <depends on folder location>
 username          Mail::Box::Net     undef

Only useful to write extension to C<Mail::Box::Net>.  Common users of
folders you will not specify these:

 OPTION            DEFINED BY         DEFAULT
 body_type         Mail::Box::Net     'Mail::Message::Body::Lines'
 body_delayed_type Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options    Mail::Box          []
 field_type        Mail::Box          undef
 head_type         Mail::Box          'Mail::Message::Head::Complete'
 head_delayed_type Mail::Box          'Mail::Message::Head::Delayed'
 locker            Mail::Box          undef
 multipart_type    Mail::Box          'Mail::Message::Body::Multipart'
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::Net::Message'
 realhead_type     Mail::Box          'Mail::Message::Head'

For each of the following options, extensions of this class may
have usefull defaults.

=over 4

=item * hostname =E<gt> HOSTNAME

The name of the host which contains the remote mail server.

=item * password =E<gt> STRING

The password which is required to contact the remote server.

=item * username =E<gt> STRING

The username which is to be used for the remote server.

=item * port =E<gt> INTEGER

Portnumber in use by the server application.

=back


=cut

sub init($)
{   my ($self, $args)    = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);

    $self->{MBN_username} = $args->{username};
    $self->{MBN_password} = $args->{password};
    $self->{MBN_hostname} = $args->{hostname};
    $self->{MBN_port}     = $args->{port};

    $self;
}

#-------------------------------------------

sub organization() { 'REMOTE' }

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
