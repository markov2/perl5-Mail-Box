
use strict;
use warnings;

package Mail::Box::MH::Message;
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::MH::Message - one message in a MH-folder

=head1 CLASS HIERARCHY

 Mail::Box::MH::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::MH::Message> represents one message in an MH-folder. Each
message is stored in a separate file.

The bottom of this page provides more details about
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

The general methods for C<Mail::Box::MH::Message> objects:

  MMC bounce OPTIONS                    MM modified [BOOL]
  MMC build [MESSAGE|BODY], CONTENT        new OPTIONS
  MMC buildFromBody BODY, HEADERS       MM nrLines
  MBM copyTo FOLDER                     MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                            MM print [FILEHANDLE]
  MBM deleted [BOOL]                   MMC quotePrelude [STRING|FIELD]
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replySubject STRING
      filename [FILENAME]               MR report [LEVEL]
  MBM folder [FOLDER]                   MR reportAll [LEVEL]
   MM get FIELD                         MM send [MAILER], OPTIONS
   MM guessTimestamp                   MBM seqnr [INTEGER]
   MM isDummy                          MBM setLabel LIST
   MM isMultipart                      MBM shortString
   MM isPart                            MM size
  MBM label STRING [ ,STRING ,...]      MM timestamp
  MBM labels                            MM toplevel
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
   MM messageId                         MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                             loadHead
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                             MR notImplemented
   MM coerce MESSAGE                       parser
  MBM diskDelete                        MM read PARSER, [BODYTYPE]
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

Messages in directory-based folders use the following options:

 OPTION      DESCRIBED IN            DEFAULT
 body        Mail::Message           undef
 body_type   Mail::Box::Message      <not used>
 deleted     Mail::Box::Message      0
 filename    Mail::Box::MH::Message  undef
 folder      Mail::Box::Message      <required>
 head        Mail::Message           undef
 head_type   Mail::Message           'Mail::Message::Head::Complete'
 head_wrap   Mail::Message           undef
 labels      Mail::Box::Message      []
 log         Mail::Reporter          'WARNINGS'
 messageId   Mail::Message           undef
 modified    Mail::Message           0
 size        Mail::Box::Message      undef
 trace       Mail::Reporter          'WARNINGS'
 trusted     Mail::Message           0

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
    my $out      = shift || \*STDOUT;

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
    @_ ? $self->{MBMM_filename} = shift : $self->{MBMM_filename};
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->SUPER::diskDelete;
    unlink $self->filename;
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
      ( filename  => $self->{MBMM_filename}
      , mode      => 'r'
      , $self->logSettings
      );

    unless($parser)
    {   $self->log(ERROR => "Cannot create parser for $self->{MBMM_filename}.");
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
    $self->read($parser);

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head + body.');
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

=back

=head1 IMPLEMENTATION

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
