
use strict;

package Mail::Box::Message::Dummy;
use base 'Mail::Box::Message';

our $VERSION = 2.016;

use Carp;

=head1 NAME

Mail::Box::Message::Dummy - a placeholder for a missing message in a list.

=head1 CLASS HIERARCHY

 Mail::Box::Message::Dummy
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Box-Overview> first.

Dummy messages are used by modules which maintain ordered lists of
messages, usually based on message-id.  A good example is
C<Mail::Box::Thread::Manager>, which detects related messages by scanning the
known message headers for references to other messages.  As long as the
referenced messages are not found inside the mailbox, their place is
occupied by a dummy.

Be careful when using modules which may create dummies.  Before trying to
access the header or body use C<isDummy()> to check if the message is a
dummy message.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC).

The general methods for C<Mail::Box::Message::Dummy> objects:

   MM bcc                               MR log [LEVEL [,STRINGS]]
  MMC bounce OPTIONS                    MM messageId
  MMC build [MESSAGE|BODY], CONTENT     MM modified [BOOL]
  MMC buildFromBody BODY, HEADERS      MBM new OPTIONS
   MM cc                                MM nrLines
  MBM copyTo FOLDER                     MM parent
   MM date                              MM parts
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
   MM label LABEL [,VALUE [LABEL,...    MR warnings
  MMC lines

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                             MR notImplemented
  MBM coerce MESSAGE                   MBM readBody PARSER, HEAD [, BO...
  MBM diskDelete                        MM readFromParser PARSER, [BOD...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM statusToLabels
   MM isDelayed                         MM storeBody BODY
   MM labels                            MM takeMessageId [STRING]

=head1 METHOD

=over 4

=cut

#-------------------------------------------

=item new MESSAGE-ID

(Class method) Create a new dummy message to occupy the space for
a real message with the specified MESSAGE-ID.

Examples:

    my $message = Mail::Box::Message::Dummy->new($msgid);
    if($message->isDummy) {...}

=cut

sub new($) { shift->SUPER::new(messageId => shift, deleted => 1) }
 
sub isDummy()    { 1 }

sub shortSize($) {"   0"};

sub shortString()
{   my $self = shift;
    sprintf "----(%2d) <not found>";
}

sub body()
{    shift->log(INTERNAL => "You cannot take the body of a dummy");
     ();
}

sub head()
{    shift->log(INTERNAL => "You cannot take the head of a dummy");
     ();
}

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
