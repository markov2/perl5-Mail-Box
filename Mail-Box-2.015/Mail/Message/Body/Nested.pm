use strict;
use warnings;

package Mail::Message::Body::Nested;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

our $VERSION = 2.015;

use Carp;

=head1 NAME

Mail::Message::Body::Nested - body of a message which contains a message

=head1 CLASS HIERARCHY

 Mail::Message::Body::Nested
 is a Mail::Message::Body + ::Construct + ::Encode
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body, plus

 if($body->isNested) {
    my ($nest) = $body->parts;
    $body->part(1)->delete;
 }

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extentions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message contains a nested message, like message/rfc822.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Body> (MMB), L<Mail::Message::Body::Construct> (MMBC), L<Mail::Message::Body::Encode> (MMBE).

The general methods for C<Mail::Message::Body::Nested> objects:

 MMBC attach MESSAGES, OPTIONS         MMB lines
  MMB charset                           MR log [LEVEL [,STRINGS]]
 MMBE check                            MMB message [MESSAGE]
  MMB checked [BOOLEAN]                MMB mimeType
 MMBC concatenate COMPONENTS           MMB modified [BOOL]
  MMB decoded OPTIONS                      nested
  MMB disposition [STRING|FIELD]           new OPTIONS
 MMBE encode OPTIONS                   MMB nrLines
 MMBE encoded                          MMB print [FILE]
  MMB eol ['CR'|'LF'|'CRLF'|'NATI...   MMB reply OPTIONS
   MR errors                            MR report [LEVEL]
  MMB file                              MR reportAll [LEVEL]
      forNested CODE                   MMB size
 MMBC foreachLine CODE                 MMB string
 MMBE isBinary                        MMBC stripSignature OPTIONS
  MMB isDelayed                         MR trace [LEVEL]
  MMB isMultipart                      MMB transferEncoding [STRING|FI...
  MMB isNested                         MMB type
 MMBE isText                            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                         MMB load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
  MMB clone                            MMB moveLocation [DISTANCE]
  MMB fileLocation [BEGIN,END]          MR notImplemented
 MMBE getTransferEncHandler TYPE       MMB read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction             MMBE unify BODY

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION      DESCRIBED IN                   DEFAULT
 based_on    Mail::Message::Body            undef
 charset     Mail::Message::Body            'us-ascii'
 data        Mail::Message::Body            undef
 disposition Mail::Message::Body            undef
 log         Mail::Reporter                 'WARNINGS'
 message     Mail::Message::Body            undef
 mime_type   Mail::Message::Body            'message/rfc822'
 modified    Mail::Message::Body            0
 nested      Mail::Message::Body::Nested    undef
 trace       Mail::Reporter                 'WARNINGS'
 transfer_encoding Mail::Message::Body      'NONE'

=over 4


=item * nested =E<gt> MESSAGE

The message which is nested within this one.
=back

Example:

 my $intro = Mail::Message::Body->new(data => ...);
 my $body  = Mail::Message::Body::Nested->new(nested  => $intro);

=cut

#------------------------------------------

sub init($)
{   my ($self, $args) = @_;
    $args->{mime_type} ||= 'message/rfc822';

    $self->SUPER::init($args);

    my $nested;
    if(my $raw = $args->{nested})
    {   my $nested = Mail::Message::Part->coerce($raw, $self);

        croak 'Data not convertable to a message (type is ', ref $raw,")\n"
            unless defined $nested;
    }

    my $based = $args->{based_on};

    $self->{MMBN_nested}
       = !$based || defined $nested  ? $nested
       : $based->isNested            ? ($based->parts)[0]
       : undef;

    $self;
}

#------------------------------------------

sub isNested() {1}

#------------------------------------------

sub isBinary() {shift->nested->isBinary}

#------------------------------------------

=item forNested CODE

Execute the CODE for the nested message.  This returns a new body object.

=cut

sub forNested($)
{   my ($self, $code) = @_;
    my $nested    = $self->nested;
    my $body      = $nested->body;
    my $new_body  = $code->($self, $body);

    return $body if $new_body == $body;

    my $new_nested  = Mail::Message->new(head => $nested->head->clone);
    $new_nested->body($new_body);

    (ref $self)->new
      ( based_on => $self
      , nested   => $new_nested
      );
}

#------------------------------------------

sub check() { shift->forNested( sub {$_[1]->check} ) }

#------------------------------------------

sub encode(@)
{   my ($self, %args) = @_;
    $self->forNested( sub {$_[1]->encode(%args)} );
}

#------------------------------------------

sub encoded() { shift->forNested( sub {$_[1]->encoded} ) }

#------------------------------------------

sub string()
{    my $nested = shift->nested;
     defined $nested ? $nested->string : '';
}

#------------------------------------------

sub lines()
{    my $nested = shift->nested;
     defined $nested ? $nested->lines : ();
}


#------------------------------------------

sub file()
{    my $nested = shift->nested;
     defined $nested ? $nested->file : undef;
}


#------------------------------------------

sub nrLines() { shift->nested->nrLines }

#------------------------------------------

sub size()    { shift->nested->size }

#------------------------------------------

sub print(;$)
{   my $self = shift;
    $self->nested->print(shift || select);
    $self;
}

#------------------------------------------

=item nested

Returns the message which is enclosed within this body.

=cut

sub nested() { shift->{MMBN_nested} }

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub read($$$$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $raw = Mail::Message->new;
    $raw->readFromParser($parser, $bodytype)
       or return;

    my $cooked = Mail::Message::Part->coerce($raw, $self);
    $self->{MMBN_nested} = $cooked;
    $self;
}

#------------------------------------------

sub clone()
{   my $self     = shift;

    my $body     = ref($self)->new
     ( $self->logSettings
     , based_on => $self
     , nested   => $self->nested->clone
     );

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
