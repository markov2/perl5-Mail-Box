
use strict;
use warnings;

package Mail::Box::Net::Message;
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::Net::Message - one message from a distant folder

=head1 CLASS HIERARCHY

 Mail::Box::Net::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::POP3 ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::Net::Message> represents one message in a folder which
can only be accessed via some kind of protocol.  On this moment, only
a POP3 client is available.  IMAP, DBI, and NNTP are other candidates.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC).

The general methods for C<Mail::Box::Net::Message> objects:

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
   MM label LABEL [,VALUE [LABEL,...       unique [unique]
  MMC lines                             MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                              loadHead
   MM body [BODY]                       MR logPriority LEVEL
   MM clone                             MR logSettings
  MBM coerce MESSAGE                    MR notImplemented
      create unique                    MBM readBody PARSER, HEAD [, BO...
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

Messages in directory-based folders use the following options:

 OPTION      DESCRIBED IN             DEFAULT
 body        Mail::Message            undef
 deleted     Mail::Box::Message       0
 unique      Mail::Box::Net::Message  <obligatory>
 folder      Mail::Box::Message       <required>
 head        Mail::Message            undef
 head_wrap   Mail::Message            undef
 labels      Mail::Box::Message       []
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

=over 4

=item * unique =E<gt> unique

The unique keys which identifies this message on the remote server.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $unique = $args->{unique}
        or croak "No unique keys for this net message.";

    $self->unique($unique);

    $self;
}

#-------------------------------------------

=item unique [unique]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub unique(;$)
{   my $self = shift;
    @_ ? $self->{MBNM_unique} = shift : $self->{MBNM_unique};
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item loadHead

This method is called by the autoloader when the header of the message
is needed.

=cut

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    my $folder   = $self->folder;
    $folder->lazyPermitted(1);

    my $parser   = $self->parser or return;
    $self->readFromParser($parser);

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head.');
    $self->head;
}

#-------------------------------------------

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->head;
    my $parser   = $self->parser or return;

    if($head->isDelayed)
    {   $head = $self->readHead($parser);
        if(defined $head)
        {   $self->log(PROGRESS => 'Loaded delayed head.');
            $self->head($head);
        }
        else
        {   $self->log(ERROR => 'Unable to read delayed head.');
            return;
        }
    }
    else
    {   my ($begin, $end) = $body->fileLocation;
        $parser->filePosition($begin);
    }

    my $newbody  = $self->readBody($parser, $head);
    unless(defined $newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);
}

#-------------------------------------------

=item create unique

Create the message in the specified file.  If the message already has
a unique and is not modified, then a move is tried.  Otherwise the
message is printed to the file.  If the unique already exists for
this message, nothing is done.  In any case, the new unique is set
as well.

=cut

sub create($)
{   my ($self, $unique) = @_;

    my $old = $self->unique || '';
    return $self if $unique eq $old && !$self->modified;

    # Write the new data to a new file.

    my $new     = $unique . '.new';
    my $newfile = IO::File->new($new, 'w');
    $self->log(ERROR => "Cannot write message to $new: $!"), return
        unless $newfile;

    $self->print($newfile);
    $newfile->close;

    # Accept the new data
# maildir produces warning where not expected...
#   $self->log(WARNING => "Failed to remove $old: $!")
#       if $old && !unlink $old;

    unlink $old if $old;

    $self->log(ERROR => "Failed to move $new to $unique: $!"), return
         unless move($new, $unique);

    $self->modified(0);
    $self->Mail::Box::Net::Message::unique($unique);

    $self;
}

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
