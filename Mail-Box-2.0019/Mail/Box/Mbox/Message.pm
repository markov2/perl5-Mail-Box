
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::Message';

our $VERSION = 2.00_19;

use POSIX 'SEEK_SET';
use IO::InnerFile;

=head1 NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=head1 CLASS HIERARCHY

 Mail::Box::Mbox::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=head1 DESCRIPTION

Maintain one message in an Mbox folder.  See the C<Mail::Message>
documentation for exceptions and extensions to messages which are
Mbox-specific on this page.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Mbox::Message> objects:

  MMC bounce OPTIONS                    MM modified [BOOL]
  MMC build [MESSAGE|BODY], CONTENT        new OPTIONS
  MMC buildFromBody BODY, HEADERS       MM nrLines
  MBM copyTo FOLDER                     MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                               print [FILEHANDLE]
  MBM deleted [BOOL]                    MM printUndisclosed [FILEHANDLE]
   MM destinations                     MMC quotePrelude [STRING|FIELD]
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replySubject STRING
  MBM folder [FOLDER]                   MR report [LEVEL]
   MM from|to|cc|bcc|date               MR reportAll [LEVEL]
      fromLine [LINE]                   MM send [MAILER], OPTIONS
   MM get FIELD                        MBM seqnr [INTEGER]
   MM guessTimestamp                   MBM setLabel LIST
   MM isDummy                          MBM shortString
   MM isMultipart                       MM size
   MM isPart                            MM subject
  MBM label STRING [ ,STRING ,...]      MM timestamp
  MBM labels                            MM toplevel
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
   MM messageId                         MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                             loadBody
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                                moveLocation DISTANCE
   MM coerce MESSAGE                    MR notImplemented
  MBM diskDelete                           parser
      fileLocation                         read PARSER
   MM head [HEAD]                      MBM readBody PARSER, HEAD [, BO...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM storeBody BODY

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MBM = L<Mail::Box::Message>
  MMC = L<Mail::Message::Construct>

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in file-based folders use the following options for creation:

 OPTION        DESCRIBED IN          DEFAULT
 body          Mail::Message         undef
 body_type     Mail::Box::Message    <defined by folder>
 deleted       Mail::Box::Message    0
 folder        Mail::Box::Message    <required>
 head          Mail::Message         undef
 head_type     Mail::Message         'Mail::Message::Head::Complete'
 head_wrap     Mail::Message         72
 labels        Mail::Box::Message    []
 log           Mail::Reporter        'WARNINGS'
 messageId     Mail::Message         undef
 modified      Mail::Message         0
 size          Mail::Box::Message    undef
 trace         Mail::Reporter        'WARNINGS'
 trusted       Mail::Message         0

=over 4

=item * from_line STRING

The line which begins each message in the file. Some people detest
this line, but this is just how things were invented...

=back

=cut

#-------------------------------------------

=item fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to generate
one.

If LINE is provided, then the starting line is set to this value.

=cut

sub fromLine(;$)
{   my $self = shift;

    $self->{MBMM_from_line} = shift if @_;
    $self->{MBMM_from_line} ||= $self->head->createFromLine;
}

#-------------------------------------------

=item print [FILEHANDLE]

Write one message to a file handle.  Unmodified messages are taken
from the folder-file where they were stored.  Modified messages
are written to memory.  Specify a FILEHANDLE to write to
(defaults to STDOUT).

=cut

sub print(;$)
{   my $self  = shift;
    my $out   = shift || \*STDOUT;

    $out->print($self->fromLine);
    $self->SUPER::print($out);
    $out->print('');
    $self;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item read PARSER

Read one message from a Mbox folder, including the message separator.
See C<Mail::Message::read()> for more details.

=cut

sub read($)
{   my ($self, $parser) = @_;
    my ($start, $fromline)  = $parser->readSeparator;
    return unless $fromline;

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;

    $self->SUPER::read($parser);

    $self->{MBMM_parser}    = $parser
        if $self->isDelayed;

    $self;
}

#-------------------------------------------

sub clone()
{   my $self  = shift;
    my $clone = $self->SUPER::clone;
    $clone->{MBMM_from_line} = $self->{MBMM_from_line};
    $clone;
}

#-------------------------------------------

=item parser

Returns the parser when there are still delayed parts of this message,
or C<undef> when all message parts are already read into real structures.

=cut

sub parser() {shift->{MBMM_parser}}

#-------------------------------------------

sub loadHead() { shift->head }

#-------------------------------------------

=item loadBody

=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
#use Carp;
#confess unless defined $body;
    return $body unless $body->isDelayed;

    my $parser   = $self->parser;
    my ($begin, $end) = $body->fileLocation;
    $parser->filePosition($begin);

    my $newbody  = $self->readBody($parser, $self->head);
    unless($newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);

    delete $self->{MBMM_parser};
    $newbody;
}

#------------------------------------------

=item fileLocation

Return the location of the whole message including the from-line.

=cut

sub fileLocation()
{   my $self = shift;
    ($self->{MBMM_begin}, ($self->body->fileLocation)[1]);
}

#------------------------------------------

=item moveLocation DISTANCE

The message is relocated in the file, being moved over DISTANCE bytes.
Setting a new location will update the according information in the header
and body.

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MBMM_begin} -= $dist;

    $self->head->moveLocation($dist);
    $self->body->moveLocation($dist);
    $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_19.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
