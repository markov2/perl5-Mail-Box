
use strict;
use warnings;

package Mail::Box::Dir::Message;
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::Dir::Message - one message in a direcory-organized folder

=head1 CLASS HIERARCHY

 Mail::Box::Dir::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::Dir::Message> represents one message in a directory
organized folder; each message is stored in a separate file.  At the
moment, two of these folder types are implemented:

=over 4

=item * MH

=item * Maildir

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC).

The general methods for C<Mail::Box::Dir::Message> objects:

   MM bcc                              MMC lines
  MMC bounce OPTIONS                    MR log [LEVEL [,STRINGS]]
  MMC build [MESSAGE|BODY], CONTENT     MM messageId
  MMC buildFromBody BODY, HEADERS       MM modified [BOOL]
   MM cc                                   new OPTIONS
  MBM copyTo FOLDER                     MM nrLines
   MM date                              MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                            MM print [FILEHANDLE]
  MBM deleted [BOOL]                   MMC printStructure [INDENT]
   MM destinations                     MMC read FILEHANDLE|SCALAR|REF-...
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replyPrelude [STRING|FIELD|...
  MMC file                             MMC replySubject STRING
      filename [FILENAME]               MR report [LEVEL]
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

The extra methods for extension writers:

   MR AUTOLOAD                             loadHead
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                             MR notImplemented
  MBM coerce MESSAGE                       parser
      create FILENAME                  MBM readBody PARSER, HEAD [, BO...
  MBM diskDelete                        MM readFromParser PARSER, [BOD...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM statusToLabels
   MM isDelayed                         MM storeBody BODY
   MM labels                            MM takeMessageId [STRING]
   MM labelsToStatus

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in directory-based folders use the following options:

 OPTION      DESCRIBED IN             DEFAULT
 body        Mail::Message            undef
 deleted     Mail::Box::Message       0
 filename    Mail::Box::Dir::Message  undef
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

=item * filename =E<gt> FILENAME

The file where the message is stored in.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->filename($args->{filename})
        if $args->{filename};

    $self;
}

#-------------------------------------------

sub print(;$)
{   my $self     = shift;
    my $out      = shift || select;

    return $self->SUPER::print($out)
        if $self->modified;

    my $filename = $self->filename;
    if($filename && -r $filename)
    {   copy($filename, $out);
        return $self;
    }

    $self->SUPER::print($out);

    1;
}

#-------------------------------------------

=item filename [FILENAME]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub filename(;$)
{   my $self = shift;
    @_ ? $self->{MBDM_filename} = shift : $self->{MBDM_filename};
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->SUPER::diskDelete;

    my $filename = $self->filename;
    unlink $filename if $filename;
    $self;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item parser

Create and return a parser for this message (-file).

=cut

sub parser()
{   my $self   = shift;

    my $parser = Mail::Box::Parser->new
      ( filename  => $self->{MBDM_filename}
      , mode      => 'r'
      , $self->logSettings
      );

    unless($parser)
    {   $self->log(ERROR => "Cannot create parser for $self->{MBDM_filename}.");
        return;
    }

    $parser;
}

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

=item create FILENAME

Create the message in the specified file.  If the message already has
a filename and is not modified, then a move is tried.  Otherwise the
message is printed to the file.  If the FILENAME already exists for
this message, nothing is done.  In any case, the new FILENAME is set
as well.

=cut

sub create($)
{   my ($self, $filename) = @_;

    my $old = $self->filename || '';
    return $self if $filename eq $old && !$self->modified;

    # Write the new data to a new file.

    my $new     = $filename . '.new';
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

    $self->log(ERROR => "Failed to move $new to $filename: $!"), return
         unless move($new, $filename);

    $self->modified(0);
    $self->Mail::Box::Dir::Message::filename($filename);

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

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
