
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::Message';

our $VERSION = 2.00_06;

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

   MM attach MESSAGES [,OPTIONS]       MBM labels
   MM body [OBJECT]                        loadBody
   MM clone                                loadHead
  MBM coerce FOLDER, MESSAGE [,OP...    MR log [LEVEL [,STRINGS]]
  MBM copyTo FOLDER                     MM messageId
  MBM delete                           MBM modified [BOOL]
  MBM deleted [BOOL]                       new OPTIONS
  MBM diskDelete                        MM parent
   MR errors                               print [FILEHANDLE]
  MBM folder [FOLDER]                   MR report [LEVEL]
      fromLine [LINE]                   MR reportAll [LEVEL]
   MM guessTimestamp                   MBM seqnr [INTEGER]
   MM head [OBJECT]                    MBM setLabel LIST
   MM isDelayed                        MBM shortString
   MM isDummy                          MBM size
   MM isMultipart                       MM timestamp
   MM isPart                            MM toplevel
  MBM label STRING [ ,STRING ,...]      MR trace [LEVEL]

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

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
 body_type         Mail::Box::Message        <defined by folder>
 deleted           Mail::Box::Message        0
 folder            Mail::Box::Message        <required>
 from_line         Mail::Box::Mbox::Message  <created from header>
 head              Mail::Message             undef
 labels            Mail::Box::Message        []
 log               Mail::Reporter            'WARNINGS'
 messageId         Mail::Message             undef
 modified          Mail::Box::Message        0
 size              Mail::Box::Message        undef
 trace             Mail::Reporter           'WARNINGS'

=over 4

=item * from_line STRING

The line which begins each message in the file. Some people detest
this line, but this is just how things were invented...

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_from_line} = $args->{from_line};
    $self->{MBM_begin}     = $args->{begin};

    $self;
}

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

    $self->{MBM_from_line} = shift if @_;

    $self->{MBM_from_line} = $self->head->createFromLine
        unless $self->{MBM_from_line};

    $self->{MBM_from_line};
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

=item loadHead

=item loadBody

This method is called by the autoloader when the data of the message
is needed.  For Mbox folders, you will always get both header and
body, even if only the header is needed.

=cut

sub loadHead($)
{   my ($self, $headtype) = @_;

    my $head = $self->head;
    return $head if $head->isDelayed;

    my $parser = $head->parser;
    unless($parser->setPosition($head->start))
    {   $self->log(ERROR => 'File reduced in size.');
        return undef;
    }

    my $newhead = $headtype->new->read($parser);
    unless($newhead)
    {   $self->log(ERROR => 'Unable to read delayed header');
        return undef;
    }
    $self->head($newhead);

    my $bodytype = $self->{MBMM_body_type};
    $bodytype = $bodytype->($head) if ref $bodytype;

    $self->body($bodytype->new->read($parser));

    $newhead;
}

sub loadBody()
{   my $self     = shift;
    my $parser   = $self->body->parser;

    my $bodytype = $self->{MBMM_body_type};
    $bodytype    = $bodytype->($self->head) if ref $bodytype;

    unless($parser->setPosition($self->body->start))
    {   $self->log(ERROR => 'File reduced in size.');
        return undef;
    }

    my $newbody = $bodytype->new->read($parser);
    unless($newbody)
    {   $self->log(ERROR => 'Unable to read delayed body');
        return undef;
    }
    $self->body($newbody);

    $newbody;
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

This code is beta, version 2.00_06.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
