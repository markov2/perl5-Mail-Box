
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::Message';

our $VERSION = 2.00_07;

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

   MM attach MESSAGES [,OPTIONS]       MBM label STRING [ ,STRING ,...]
   MM body [OBJECT]                    MBM labels
   MM clone                             MR log [LEVEL [,STRINGS]]
  MBM coerce FOLDER, MESSAGE [,OP...    MM messageId
  MBM copyTo FOLDER                    MBM modified [BOOL]
  MBM delete                               new OPTIONS
  MBM deleted [BOOL]                    MM parent
  MBM diskDelete                           print [FILEHANDLE]
   MR errors                            MR report [LEVEL]
  MBM folder [FOLDER]                   MR reportAll [LEVEL]
      fromLine [LINE]                  MBM seqnr [INTEGER]
   MM guessTimestamp                   MBM setLabel LIST
   MM head [OBJECT]                    MBM shortString
   MM isDelayed                        MBM size
   MM isDummy                           MM timestamp
   MM isMultipart                       MM toplevel
   MM isPart                            MR trace [LEVEL]

The extra methods for extension writers:

      loadBody                          MR logSettings
      loadHead [CLASS]                  MR notImplemented
   MR logPriority LEVEL                    parser

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
 modified          Mail::Box::Message        0
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

=item read FOLDER, PARSER, HEADCLASS

Read one message from a Mbox folder, including the message separator.

=cut

sub read($$$)
{   my ($class, $folder, $parser, $headtype) = @_;
    my ($start, $fromline) = $parser->readSeparator;
    last unless defined $start;

    unless($fromline)
    {   $folder->log(ERROR => "Folder not fully read.");
        return;
    }

    my @log      = $folder->logSettings;
    my $head     = $headtype->new(@log)->read($parser)
        or return;

    my $lines    = $head->get('Lines');
    my $size     = $head->guessBodySize;

    my $bodytype = $folder->readBodyType($head, $size, 1);
#warn "BODYTYPE=$bodytype.\n";
    my $body     = $bodytype->new->read($parser, $size, $lines)
        or return;

    my $self     = $class->new(@log);
    $self->{MBMM_begin}     = $start;
    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_parser}    = $parser
        if $bodytype->isDelayed;

    $self->head($head);
    $self->body($body);
    $self->statusToLabels->XstatusToLabels;

    $self;
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

    my $newhead = $headtype->new(head->logSettings)->read($parser);
    if($newhead) { $self->log(PROGRESS => 'Loaded delayed head.') }
    else         { $self->log(ERROR    => 'Unable to read delayed head.') }

    $self->head($newhead);
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
    my $bodytype = $folder->readBodyType($head, $self->guessBodySize, 0);

    my $parser   = $self->parser;
    $parser->setPosition($body->start);

    my $newbody  = $bodytype->new($head->logSettings)->read($parser);

    if($newbody) { $self->log(PROGRESS => 'Loaded delayed body.') }
    else         { $self->log(ERROR    => 'Unable to read delayed body.') }

    delete $self->{MBMM_parser};
    $self->body($newbody);
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

This code is beta, version 2.00_07.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
