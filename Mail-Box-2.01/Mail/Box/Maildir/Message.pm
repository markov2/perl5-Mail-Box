
use strict;
use warnings;

package Mail::Box::Maildir::Message;
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::Maildir::Message - one message in a Maildir folder

=head1 CLASS HIERARCHY

 Mail::Box::Maildir::Message
 is a Mail::Box::Dir::Message
 is a Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::Maildir ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::Maildir::Message> represents one message in an
Maildir-folder. Each message is stored in a separate file.

The bottom of this page provides more details about
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Box::Message> (MBM), L<Mail::Message::Construct> (MMC), L<Mail::Box::Dir::Message> (MBDM).

The general methods for C<Mail::Box::Maildir::Message> objects:

   MM bcc                               MM label LABEL [,VALUE [LABEL,...
  MMC bounce OPTIONS                    MR log [LEVEL [,STRINGS]]
  MMC build [MESSAGE|BODY], CONTENT     MM messageId
  MMC buildFromBody BODY, HEADERS       MM modified [BOOL]
   MM cc                                   new OPTIONS
  MBM copyTo FOLDER                     MM nrLines
   MM date                              MM parent
   MM decoded OPTIONS                   MM parts
  MBM delete                            MM print [FILEHANDLE]
  MBM deleted [BOOL]                    MM printUndisclosed [FILEHANDLE]
   MM destinations                     MMC reply OPTIONS
   MM encode OPTIONS                   MMC replyPrelude [STRING|FIELD|...
   MR errors                           MMC replySubject STRING
      filename [FILENAME]               MR report [LEVEL]
  MBM folder [FOLDER]                   MR reportAll [LEVEL]
  MMC forward OPTIONS                   MM send [MAILER], OPTIONS
  MMC forwardPostlude                  MBM seqnr [INTEGER]
  MMC forwardPrelude                   MBM shortString
  MMC forwardSubject STRING             MM size
   MM from                              MM subject
   MM get FIELD                         MM timestamp
   MM guessTimestamp                    MM to
   MM isDummy                           MM toplevel
   MM isMultipart                       MR trace [LEVEL]
   MM isPart                            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                         MBDM loadHead
   MM body [BODY]                       MR logPriority LEVEL
   MM clone                             MR logSettings
   MM coerce MESSAGE                    MR notImplemented
  MBM diskDelete                      MBDM parser
      guessTimestamp                    MM read PARSER, [BODYTYPE]
   MM head [HEAD]                      MBM readBody PARSER, HEAD [, BO...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM statusToLabels
   MM labels                            MM storeBody BODY
      labelsToFilename                  MM takeMessageId [STRING]

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in directory-based folders use the following options:

 OPTION      DESCRIBED IN            DEFAULT
 body        Mail::Message           undef
 deleted     Mail::Box::Message      0
 filename    Mail::Box::Maildir::Message  undef
 folder      Mail::Box::Message      <required>
 head        Mail::Message           undef
 head_wrap   Mail::Message           undef
 log         Mail::Reporter          'WARNINGS'
 messageId   Mail::Message           undef
 modified    Mail::Message           0
 size        Mail::Box::Message      undef
 trace       Mail::Reporter          'WARNINGS'
 trusted     Mail::Message           0

Only for extension writers:

 OPTION      DESCRIBED IN            DEFAULT
 body_type   Mail::Box::Message      <not used>
 field_type  Mail::Message           undef
 head_type   Mail::Message           'Mail::Message::Head::Complete'

=over 4

=item * filename =E<gt> FILENAME

The file where the message is stored in on the moment.  For maildir
messages, this name can change all the time.

=back

=cut

#-------------------------------------------

=item filename [FILENAME]

Returns the current filename for this message.  If the FILENAME argument
is specified, a new filename will be set.  For maildir messages this
means that modifications are immediately performed: there will be
a rename (move) from the old name to the new name.  Labels may change
within in the message object as well.

=cut

sub filename(;$)
{   my $self = shift;
    my $old  = $self->SUPER::filename;
    return $old unless @_;

    my $new  = shift;
    return $new if defined $old && $old eq $new;

    my ($id, $semantics, $flags) =
        $new =~ m!(.*?)(?:\:([12])\,([A-Z]*))! ? ($1, $2, $3) : ($new, '','');

    my %flags;
    $flags{$_}++ foreach split //, $flags;

    $self->SUPER::label
     ( draft   => ($flags{D} || 0)
     , flagged => ($flags{F} || 0)
     , replied => ($flags{R} || 0)
     , seen    => ($flags{S} || 0)
     );

    $self->SUPER::deleted($flags{T} || 0);

    if(defined $old)
    {   move $old, $new
           or confess "Cannot move $old to $new: $!";
    }

    $self->SUPER::filename($new);
}

#-------------------------------------------

sub deleted($)
{   my $self = shift;
    return $self->SUPER::deleted unless @_;

    my $set  = shift;
    $self->SUPER::deleted($set);
    $self->labelsToFilename;
    $set;
}

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    return $self->SUPER::label unless @_;

    my $return = $self->SUPER::label(@_);
    $self->labelsToFilename;
    $return;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item labelsToFilename

When the labels on a message change, this may implicate a change in
the message's filename.  The change will take place immediately.

=cut

sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $oldname) = $old =~ m!(.*)/(?:new|cur)/([^:]*)(\:[^:]*)?$!;
    my $newflags
      = ($labels->{draft}      ? 'D' : '')    # flags must be alphabetic
      . ($labels->{flagged}    ? 'F' : '')
      . ($labels->{replied}    ? 'R' : '')
      . ($labels->{seen}       ? 'S' : '')
      . ($self->SUPER::deleted ? 'T' : '');

    my $new = File::Spec->catfile($folderdir, cur => "$oldname:2,$newflags");

    if($new ne $old)
    {   unless(move $old, $new)
        {   warn "Cannot rename $old to $new: $!";
            return;
        }
        $self->log(PROGRESS => "Moved $old to $new.");
        $self->SUPER::filename($new);
    }

    $new;
}

#-------------------------------------------

=item guessTimestamp

The filename of a C<Mail::Box::Maildir::Message> contains a timestamp.  This
is a wild guess about the actual time of sending of the message: it is the
time of receipt which may be seconds to hours off.  But is still a good
guess...  When the message header is not parsed, then this date is used.

=cut

sub guessTimestamp()
{   my $self = shift;
    my $timestamp   = $self->SUPER::guessTimestamp;
    return $timestamp if defined $timestamp;

    $self->filename =~ m/(\d+)/ ? $1 : undef;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.010.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
