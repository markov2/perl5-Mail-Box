use strict;
use warnings;

package Mail::Message::Part;
use base 'Mail::Message';

our $VERSION = 2.014;

use Carp;

=head1 NAME

Mail::Message::Part - a part of a message, but a message by itself.

=head1 CLASS HIERARCHY

 Mail::Message::Part
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $message = ...;
 if($message->isMultipart) {
     my Mail::Message::Part $part;

     foreach $part ($message->body->parts) {
         $part->print(\*OUT);
         my $attachbody = $part->head;
         my $attachhead = $part->body;
     }
 }

=head1 DESCRIPTION

A C<Mail::Message::Part> object contains a message which is included in
an other message.  For instance I<attachments> are I<parts>.

READ C<Mail::Message> FIRST.  A part is a special message: it has a
reference to its parent message, and will usually not be sub-classed
into mail-folder-specific variants.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message> (MM), L<Mail::Reporter> (MR), L<Mail::Message::Construct> (MMC).

The general methods for C<Mail::Message::Part> objects:

   MM bcc                               MR log [LEVEL [,STRINGS]]
  MMC bounce OPTIONS                    MM messageId
  MMC build [MESSAGE|BODY], CONTENT     MM modified [BOOL]
      buildFromBody BODY, MULTIPA...       new OPTIONS
   MM cc                                MM nrLines
   MM date                              MM parent
   MM decoded OPTIONS                   MM parts
   MM destinations                      MM print [FILEHANDLE]
   MM encode OPTIONS                   MMC read FILEHANDLE|SCALAR|REF-...
   MR errors                           MMC reply OPTIONS
  MMC forward OPTIONS                  MMC replyPrelude [STRING|FIELD|...
  MMC forwardPostlude                  MMC replySubject STRING
  MMC forwardPrelude                    MR report [LEVEL]
  MMC forwardSubject STRING             MR reportAll [LEVEL]
   MM from                              MM send [MAILER], OPTIONS
   MM get FIELD                         MM size
   MM guessTimestamp                    MM subject
   MM isDummy                           MM timestamp
   MM isMultipart                       MM to
   MM isPart                            MM toplevel
   MM label LABEL [,VALUE [LABEL,...    MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MM labelsToStatus
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
      clone                             MR notImplemented
      coerce BODY|MESSAGE, MULTIPART    MM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readFromParser PARSER, [BOD...
   MR inGlobalDestruction               MM readHead PARSER [,CLASS]
   MM isDelayed                         MM statusToLabels
   MM labels                            MM storeBody BODY

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a message part.  You can add the following options:

 OPTIONS              DESCRIBED IN           DEFAULT
 body                 Mail::Message          <undef>
 head                 Mail::Message          <undef>
 parent               Mail::Message::Part    <obligatory>

=over 4

=item * parent =E<gt> MESSAGE

(obligatory) reference to the parental C<Mail::Message> object where this
part is a member of.  That object may be a part itself.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMP_parent} = $args->{parent}
        or confess "No parent specified for part.\n";

    $self;
}

sub parent()     { shift->{MMP_parent} }           # overrides
sub toplevel()   { shift->{MMP_parent}->toplevel } # idem
sub isPart()     { 1 }                             # idem

#------------------------------------------

=item buildFromBody BODY, MULTIPART, HEADERS

(Class method)
Shape a message part around a BODY.  Bodies have information about their
content in them, which is used to construct a header for the attachment.
The MULTIPART refers to the parent body which is a multipart.

Next to that, more HEADERS can be specified as key-value combinations
or C<Mail::Message::Field> objects.  These are added in order, and
before the data from the body is taken.  No fields are obligatory.

Example:

 my $part = Mail::Message::Part->buildFromBody($body, $parent);

=cut

sub buildFromBody($$)
{   my ($class, $body, $parent) = (shift, shift, shift);
    my @log     = $body->logSettings;

    my $head    = Mail::Message::Head::Complete->new(@log);
    while(@_)
    {   if(ref $_[0]) {$head->add(shift)}
        else          {$head->add(shift, shift)}
    }

    my $part = $class->new
     ( head   => $head
     , parent => $parent
     , @log
     );

    $part->body($body);
    $part;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item coerce BODY|MESSAGE, MULTIPART

In extension to full messages, message parts can be coerced from a
BODY C<Mail::Message::Body>.  This is because the body data contains
enough information.  The MULTIPART refers to the parent body.

Parts can be build from C<Mail::Message::Body>, C<Mail::Message>,
C<Mail::Internet>, and C<MIME::Entity> objects.

=cut

sub coerce($@)
{   my ($class, $message, $parent) = @_;

    return Mail::Message::Part->buildFromBody($message, $parent)
        if $message->isa('Mail::Message::Body');

    my $part = $class->SUPER::coerce($message);
    $part->{MMP_parent} = $parent;
    $part;
}

#------------------------------------------

=item clone

A message part is cloned as plain message, and may be added as such
to a folder.  It will be coerced into a part when added to a multi-part
body.

=cut

sub clone()
{   my $self = shift;
    Mail::Message->new
     ( body  => $self->body->clone
     , head  => $self->head->clone
     , $self->logSettings
     );
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.014.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
