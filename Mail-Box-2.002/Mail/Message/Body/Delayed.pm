use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Object::Realize::Later
    becomes          => 'Mail::Message::Body',
    realize          => 'load',
    warn_realization => 0,
    believe_caller   => 1;

use overload '""'    => sub {shift->load->string}
           , bool    => sub {1}
           , '@{}'   => sub {shift->load->lines};

use Carp;
use Scalar::Util 'weaken';

our $VERSION = 2.00_20;

=head1 NAME

Mail::Message::Body::Delayed - body of a Mail::Message but not read yet.

=head1 CLASS HIERARCHY

 Mail::Message::Body::Delayed realizes Mail::Message::Body + ::Construct + ::Encode
 is a Mail::Reporter                   is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

Read C<Mail::Message::Body> and C<Mail::Box-Overview> first.
Message bodies of this type will be replaced by another type the moment you
access the content.  In this documentation you will find the description of
how a message body gets delay loaded.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Delayed> objects:

 MMBC attach MESSAGES, OPTIONS         MMB message [MESSAGE]
 MMBE check                            MMB mimeType
  MMB checked [BOOLEAN]                MMB modified [BOOL]
 MMBC concatenate COMPONENTS               new OPTIONS
  MMB decoded OPTIONS                  MMB nrLines
  MMB disposition [STRING|FIELD]       MMB print [FILE]
 MMBE encode OPTIONS                   MMB reply OPTIONS
 MMBE encoded                           MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MMB file                             MMB size
 MMBC foreachLine CODE                 MMB string
 MMBE isBinary                        MMBC stripSignature OPTIONS
  MMB isDelayed                         MR trace [LEVEL]
  MMB isMultipart                      MMB transferEncoding [STRING|FI...
  MMB lines                            MMB type
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                             load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
  MMB clone                            MMB moveLocation [DISTANCE]
  MMB fileLocation                      MR notImplemented
 MMBE getTransferEncHandler TYPE       MMB read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction             MMBE unify BODY

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>
 MMBC = L<Mail::Message::Body::Construct>
 MMBE = L<Mail::Message::Body::Encode>

=head1 METHODS

The body will currently only stay delayed when you call
for C<isDelayed>, C<message>, C<guessSize>, and maybe for C<isMultipart>
and C<nrLines>.  In all ot

=over 4

=cut

#------------------------------------------

=item new OPTIONS

The constuctor used the following options:

 OPTION    DESCRIBED IN                  DEFAULT
 data      Mail::Message::Body           <ignored>
 log       Mail::Reporter                'WARNINGS'
 message   Mail::Message::Body           undef
 modified  Mail::Message::Body           <ignored>
 trace     Mail::Reporter                'WARNINGS'

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMBD_message} = $args->{message}
        or croak "A message must be specified to a delayed body.";

    weaken($self->{MMBD_message});
    $self;
}

#------------------------------------------

sub message() {shift->{MMBD_message}}

#------------------------------------------

sub isDelayed()   {1}
sub isMultipart() {shift->message->head->isMultipart}
sub guessSize()   {shift->{MMBD_size}}

#------------------------------------------

sub nrLines()
{   my ($self) = @_;
      defined $self->{MMBD_lines}
    ? $self->{MMBD_lines}
    : $_[0]->forceRealize->nrLines;
}

#------------------------------------------

sub modified(;$)
{   return 0 if @_==1 || !$_[1];
    shift->forceRealize(shift);
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    $self->{MMBD_parser} = $parser;

    @$self{ qw/MMBD_begin MMBD_end MMBD_size MMBD_lines/ }
        = $parser->bodyDelayed(@_);

    $self;
}

#------------------------------------------

sub fileLocation() {
   my $self = shift;
   @$self{ qw/MMBD_begin MMBD_end/ };
}

#------------------------------------------

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMBD_begin} -= $dist;
    $self->{MMBD_end}   -= $dist;
    $self;
}

#------------------------------------------

=item load

Returns the loaded version of this body.

=cut

sub load() {$_[0] = $_[0]->message->loadBody}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_20.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
