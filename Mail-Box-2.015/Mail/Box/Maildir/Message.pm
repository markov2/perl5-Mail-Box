

package Mail::Box::Maildir::Message;
use base 'Mail::Box::Dir::Message';

use strict;
use File::Copy;
use Carp;
use warnings;

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

   MR AUTOLOAD                             labelsToFilename
   MM DESTROY                           MM labelsToStatus
      accept                          MBDM loadHead
   MM body [BODY]                       MR logPriority LEVEL
   MM clone                             MR logSettings
  MBM coerce MESSAGE                    MR notImplemented
 MBDM create FILENAME                 MBDM parser
  MBM diskDelete                       MBM readBody PARSER, HEAD [, BO...
      guessTimestamp                    MM readFromParser PARSER, [BOD...
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

 OPTION      DESCRIBED IN            DEFAULT
 body        Mail::Message           undef
 deleted     Mail::Box::Message      0
 filename    Mail::Box::Dir::Message undef
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
{   my $self    = shift;
    my $oldname = $self->SUPER::filename;
    return $oldname unless @_;

    my $newname = shift;
    return $newname if defined $oldname && $oldname eq $newname;

    my ($id, $semantics, $flags)
     = $newname =~ m!(.*?)(?:\:([12])\,([A-Z]*))!
     ? ($1, $2, $3)
     : ($newname, '','');

    my %flags;
    $flags{$_}++ foreach split //, $flags;

    $self->SUPER::label
     ( draft   => ($flags{D} || 0)
     , flagged => ($flags{F} || 0)
     , replied => ($flags{R} || 0)
     , seen    => ($flags{S} || 0)
     );

    $self->SUPER::deleted($flags{T} || 0);

    if(defined $oldname)
    {   move $oldname, $newname
           or confess "Cannot move $oldname to $newname: $!";
    }

    $self->SUPER::filename($newname);
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

=item accept

Accept a message for the folder.  This will move it from the C<new> or
C<tmp> sub-directories into the C<cur> sub-directory.  When you accept an
already accepted message, nothing will happen.

=cut

sub accept($)
{   my $self   = shift;
    my $old    = $self->filename;

    unless($old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$! )
    {   $self->log(ERROR => "filename $old is not in a Maildir folder.\n");
        return undef;
    }

    return $self if $2 eq 'cur';
    my $new = "$1/cur/$3";

    $self->log(PROGRESS => "Message $old is accepted.\n");
    $self->filename($new);
}

#-------------------------------------------

=item labelsToFilename

When the labels on a message change, this may implicate a change in
the message's filename.  The change will take place immediately.

=cut

sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $set, $oldname)
      = $old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$!;

    my $newflags
      = ($labels->{draft}      ? 'D' : '')    # flags must be alphabetic
      . ($labels->{flagged}    ? 'F' : '')
      . ($labels->{replied}    ? 'R' : '')
      . ($labels->{seen}       ? 'S' : '')
      . ($self->SUPER::deleted ? 'T' : '');

    my $new = File::Spec->catfile($folderdir, $set, "$oldname:2,$newflags");

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

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.015.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
