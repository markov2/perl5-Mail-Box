
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::Message';

our $VERSION = 2.00_09;

use POSIX 'SEEK_SET';
use IO::InnerFile;

=head1 NAME

 Mail::Box::Mbox::Message - one message in a Mbox folder

=head1 CLASS HIERARCHY

 Mail::Box::Mbox::Message
 is a Mail::Box::Message
 is a Mail::Message
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

   MM attach MESSAGES [,OPTIONS]        MR log [LEVEL [,STRINGS]]
  MBM copyTo FOLDER                     MM messageId
   MM decoded OPTIONS                   MM modified [BOOL]
  MBM delete                               new OPTIONS
  MBM deleted [BOOL]                    MM nrLines
   MM encode TYPE                       MM parent
   MR errors                               print [FILEHANDLE]
  MBM folder [FOLDER]                   MR report [LEVEL]
      fromLine [LINE]                   MR reportAll [LEVEL]
   MM get FIELD                        MBM seqnr [INTEGER]
   MM guessTimestamp                   MBM setLabel LIST
   MM isDelayed                        MBM shortString
   MM isDummy                           MM size
   MM isMultipart                       MM timestamp
   MM isPart                            MM toplevel
  MBM label STRING [ ,STRING ,...]      MR trace [LEVEL]
  MBM labels                            MR warnings

The extra methods for extension writers:

   MM body [BODY]                          loadHead [CLASS]
   MM clone                             MR logPriority LEVEL
   MM coerce MESSAGE [,OPTIONS]         MR logSettings
  MBM diskDelete                        MR notImplemented
   MM head [OBJECT]                        parser
      loadBody                             read PARSER, HEADTYPE, BODY...

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MBM = L<Mail::Box::Message>

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in file-based folders use the following options for creation:

 OPTION            DESCRIBED IN              DEFAULT
 body              Mail::Message             undef
 deleted           Mail::Box::Message        0
 folder            Mail::Box::Message        <required>
 head              Mail::Message             undef
 labels            Mail::Box::Message        []
 log               Mail::Reporter            'WARNINGS'
 messageId         Mail::Message             undef
 modified          Mail::Message             0
 size              Mail::Box::Message        undef
 trace             Mail::Reporter           'WARNINGS'

OPTIONS for extension writers:

 OPTION            DESCRIBED IN              DEFAULT
 body_type         Mail::Box::Message        <defined by folder>

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

=item read PARSER, HEADTYPE, BODYTYPE

Read one message from a Mbox folder, including the message separator.
See C<Mail::Message::read()> for more details.

=cut

sub read($$$)
{   my ($self, $parser, $headtype, $bodytype) = @_;
    my ($start, $fromline) = $parser->readSeparator;
    return unless $fromline;

    $self->SUPER::read($parser, $headtype, $bodytype);

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;
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

=item loadHead [CLASS]

This method is called by the autoloader when the header of the message
is needed.  The CLASS specifies the type of header to be made, which
must be a complete header -extend C<Mail::Message::Head::Complete>.

=cut

sub loadHead(;$)
{   my ($self, $headtype) = @_;

    my $head    = $self->head;
    return $head unless $head->isDelayed;

    my $parser  = $self->parser;
    $parser->setPosition($head->start);

    my $newhead = $headtype->new(head->logSettings, message => $self)
                           ->read($parser);

    if($newhead) { $self->log(PROGRESS => 'Loaded delayed head.') }
    else         { $self->log(ERROR    => 'Unable to read delayed head.') }

    $self->{MM_head} = $newhead;
}

#-------------------------------------------

=item loadBody

=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->loadHead;
    my $folder   = $self->folder;
    my $bodytype = $folder->readBodyType($head, $head->guessBodySize, 0);

    my $parser   = $self->parser;
    $parser->setPosition($body->start);

    my $getbodytype
      = $bodytype->isMultipart
      ? sub {$folder->readBodyType($_[0], $_[1], 0)}
      : sub {$bodytype};

    my $newbody  = $bodytype->new($head->logSettings, message => $self)
                     ->read($parser, $head, $getbodytype);

    if($newbody) { $self->log(PROGRESS => 'Loaded delayed body.') }
    else         { $self->log(ERROR    => 'Unable to read delayed body.') }

    delete $self->{MBMM_parser};
    $self->{MM_body} = $newbody;
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

This code is beta, version 2.00_09.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
