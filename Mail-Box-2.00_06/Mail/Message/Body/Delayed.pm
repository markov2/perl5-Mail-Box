use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Carp;

use Object::Realize::Later
    becomes => 'Mail::Message::Body',
    warn_realization => 1,
    realize => sub {shift->message->loadBody};

our $VERSION = '2.00_06';

=head1 NAME

Mail::Message::Body::Delayed - Body of a Mail::Message but not read yet.

=head1 CLASS HIERARCHY

 Mail::Message::Body::Delayed realizes Mail::Message::Body
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

  MMB clone                            MMB nrLines
  MMB data FILE | LIST-OF-LINES |...   MMB print [FILE]
   MR errors                           MMB read PARSER [,CHARS [,LINES]]
  MMB file                             MMB reply OPTIONS
  MMB isDelayed                         MR report [LEVEL]
  MMB isMultipart                       MR reportAll [LEVEL]
  MMB lines                            MMB size
   MR log [LEVEL [,STRINGS]]           MMB string
  MMB message [MESSAGE]                MMB stripSignature OPTIONS
      new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>

=head1 METHODS

The body will currently only stay delayed when you call
for C<isDelayed>, C<message>, C<guessSize>, and maybe for C<isMultipart>
and C<nrLines>.  In all ot

=over 4

=item new OPTIONS

The constuctor used the following options:

 OPTION    DESCRIBED IN                  DEFAULT
 log       Mail::Reporter                'WARNINGS'
 message   Mail::Message::Body           undef
 size      Mail::Message::Body           undef
 trace     Mail::Reporter                'WARNINGS'

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{MMBD_message} = $args->{message};
    $self->{MMBD_size}    = $args->{size};
    $self;
}

sub message()
{   my $self = shift;
    @_ ? $self->{MMBD_message} = shift : $self->{MMBD_message};
}

sub isDelayed()   {1}
sub isMultipart() {shift->message->head->isMultipart}
sub guessSize()   {shift->{MMBD_size}}

sub nrLines()
{   my ($self) = @_;
      defined $self->{MMBD_lines}
    ? $self->{MMBD_lines}
    : $_[0]->forceRealize->nrLines;
}

sub read($;@)
{   my ($self, $parser) = (shift, shift);
    $self->{MMBD_parser} = $parser;
    @$self{ qw/MMBD_where MMBD_size MMBD_lines/ } = $parser->bodyDelayed(@_);
    $self;
}

sub parser() {shift->{MMBD_parser}}
sub start()  {shift->{MMBD_where}}

#------------------------------------------

=back

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