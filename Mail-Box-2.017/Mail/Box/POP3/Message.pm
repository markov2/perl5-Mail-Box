
use strict;
use warnings;

package Mail::Box::POP3::Message;
use base 'Mail::Box::Net::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::POP3::Message - one message on a POP3 server

=head1 CLASS HIERARCHY

 Mail::Box::POP3::Message
 is a Mail::Box::Net::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::POP3 ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::POP3::Message> represents one message on a POP3 server. Each
message is stored is stored as separate entity on the server, and maybe
temporarily in your program as well.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC), L<Mail::Box::Net::Message> (MBNM).

The general methods for C<Mail::Box::POP3::Message> objects:

   MM bcc                               MR log [LEVEL [,STRINGS]]
  MMC bounce OPTIONS                    MM messageId
  MMC build [MESSAGE|BODY], CONTENT     MM modified [BOOL]
  MMC buildFromBody BODY, HEADERS          new OPTIONS
   MM cc                                MM nrLines
  MBM copyTo FOLDER                     MM parent
   MM date                              MM parts ['ALL'|'ACTIVE'|'DELE...
   MM decoded OPTIONS                   MM print [FILEHANDLE]
  MBM delete                           MMC printStructure [INDENT]
  MBM deleted [BOOL]                   MMC read FILEHANDLE|SCALAR|REF-...
   MM destinations                     MMC reply OPTIONS
   MM encode OPTIONS                   MMC replyPrelude [STRING|FIELD|...
   MR errors                           MMC replySubject STRING
  MMC file                              MR report [LEVEL]
  MBM folder [FOLDER]                   MR reportAll [LEVEL]
  MMC forward OPTIONS                   MM send [MAILER], OPTIONS
  MMC forwardPostlude                  MBM seqnr [INTEGER]
  MMC forwardPrelude                   MBM shortString
  MMC forwardSubject STRING             MM size
   MM from                             MMC string
   MM get FIELD                         MM subject
   MM guessTimestamp                    MM timestamp
   MM isDummy                           MM to
   MM isMultipart                       MM toplevel
   MM isPart                            MR trace [LEVEL]
   MM label LABEL [,VALUE [LABEL,...  MBNM unique [unique]
  MMC lines                             MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                         MBNM loadHead
   MM body [BODY]                       MR logPriority LEVEL
   MM clone                             MR logSettings
  MBM coerce MESSAGE                    MR notImplemented
 MBNM create unique                    MBM readBody PARSER, HEAD [, BO...
  MBM diskDelete                        MM readFromParser PARSER, [BOD...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM statusToLabels
   MM isDelayed                         MM storeBody BODY
   MM labels                            MM takeMessageId [STRING]

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in POP3 folders use the following options:

 OPTION      DESCRIBED IN             DEFAULT
 body        Mail::Message            undef
 deleted     Mail::Box::Message       0
 folder      Mail::Box::Message       <required>
 head        Mail::Message            undef
 head_wrap   Mail::Message            undef
 log         Mail::Reporter           'WARNINGS'
 messageId   Mail::Message            undef
 modified    Mail::Message            0
 size        Mail::Box::Message       undef
 trace       Mail::Reporter           'WARNINGS'
 trusted     Mail::Message            0

Only for extension writers:

 OPTION      DESCRIBED IN             DEFAULT
 body_type   Mail::Box::Message       <not used>
 field_type  Mail::Message            undef
 head_type   Mail::Message            'Mail::Message::Head::Complete'

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $args->{MBPM_uidl} = $args->{uidl}
        or croak "No uidl specified for POP3 message.";

    $self;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

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

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
