use strict;
use warnings;

package Mail::Message::Part;
use base 'Mail::Message';

our $VERSION = '2.00_14';

use Carp;

=head1 NAME

Mail::Message::Part - a part of a Mail::Message, but a message by itself.

=head1 CLASS HIERARCHY

 Mail::Message::Part
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $message = ...;
 if($message->isMultipart) {
     my Mail::Message::Part $part;

     foreach $part ($message->body->parts) {
         $part->print(\*STDOUT);
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

The general methods for C<Mail::Message::Part> objects:

  MMC build OPTIONS                        new OPTIONS
  MMC buildFromBody BODY, HEADERS       MM nrLines
   MM decoded OPTIONS                   MM parent
   MM encode OPTIONS                    MM print [FILEHANDLE]
   MR errors                           MMC quotePrelude [STRING|FIELD]
   MM get FIELD                        MMC reply OPTIONS
   MM guessTimestamp                   MMC replySubject STRING
   MM isDummy                           MR report [LEVEL]
   MM isMultipart                       MR reportAll [LEVEL]
   MM isPart                            MM size
   MR log [LEVEL [,STRINGS]]            MM timestamp
   MM messageId                         MM toplevel
   MM modified [BOOL]                   MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MM DESTROY                           MR logSettings
   MM body [BODY]                       MR notImplemented
   MM clone                             MM read PARSER, [BODYTYPE]
   MM coerce MESSAGE [,OPTIONS]         MM readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM storeBody BODY
   MM isDelayed                         MM takeMessageId [STRING]

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MMC = L<Mail::Message::Construct>

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

sub parent()     { shift->{MMP_parent} }            # overrides
sub toplevel()   { shift->{MMP_parent}->toplevel }  # idem
sub isPart()     { 1 }                             # idem

#------------------------------------------


=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_14.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
