
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
   MM destinations                     MMC read FILEHANDLE|SCALAR|REF-...
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replyPrelude [STRING|FIELD|...
      filename [FILENAME]              MMC replySubject STRING
  MBM folder [FOLDER]                   MR report [LEVEL]
  MMC forward OPTIONS                   MR reportAll [LEVEL]
  MMC forwardPostlude                   MM send [MAILER], OPTIONS
  MMC forwardPrelude                   MBM seqnr [INTEGER]
  MMC forwardSubject STRING            MBM shortString
   MM from                              MM size
   MM get FIELD                         MM subject
   MM guessTimestamp                    MM timestamp
   MM isDummy                           MM to
   MM isMultipart                       MM toplevel
   MM isPart                            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                             labelsToFilename
   MM DESTROY                           MM labelsToStatus
   MM body [BODY]                     MBDM loadHead
   MM clone                             MR logPriority LEVEL
   MM coerce MESSAGE                    MR logSettings
 MBDM create FILENAME                   MR notImplemented
  MBM diskDelete                      MBDM parser
      guessTimestamp                   MBM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readFromParser PARSER, [BOD...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM statusToLabels
   MM labels                            MM storeBody BODY

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

sub clone()
{   my $self     = shift;
    my $clone    = $self->SUPER::clone();
    my $filename = $self->SUPER::filename;
    my $clonename;

    if(my ($b,$nr, $f) = $filename =~ m/(.*?)(\d*)(\:[^:]*)$/)
         {$clonename = $b.++$nr.$f }
    else {$clonename = ++$filename}

    $clone->SUPER::filename($clonename);
    $clone->labelsToFilename;

    my $clonefn = $clone->filename;
    unless(open OUT, '>', $clonefn)
    {   carp "Cannot create $clonefn: $!";
        return undef;
    }
    $clone->print(\*OUT);
    close OUT;

    $clone;
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
confess unless $old;

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

This code is beta, version 2.012.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
