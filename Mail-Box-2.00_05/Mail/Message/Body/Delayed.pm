use strict;
use warnings;

package Mail::Message::Body::Delayed;
use base 'Mail::Reporter';

use Object::Realize::Later
    becomes => 'Mail::Message::Body',
    realize => sub {shift->message->loadBody};

our $VERSION = '2.00_05';

use Carp;

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

  MMB clone                             MR new OPTIONS
  MMB data FILE | LIST-OF-LINES |...   MMB nrLines
   MR errors                           MMB print [FILE]
  MMB file                             MMB read PARSER [,CHARS [,LINES]]
  MMB isDelayed                        MMB reply OPTIONS
  MMB isMultipart                       MR report [LEVEL]
  MMB lines                             MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]           MMB size
  MMB message [MESSAGE]                MMB string
      new OPTIONS                      MMB stripSignature OPTIONS
  MMB new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

    MR = L<Mail::Reporter>
   MMB = L<Mail::Message::Body>


=head1 METHODS

The body will currently only stay delayed when you call
for C<isDelayed>, C<message>, C<guessSize>, and maybe for C<isMultipart>.

=over 4

=item new OPTIONS

The constuctor used the following options:

 OPTION            DESCRIBED IN          DEFAULT
 log               Mail::Reporter        'WARNINGS'
 message           Mail::Message::Body   undef
 size              Mail::Message::Body   undef
 trace             Mail::Reporter        'WARNINGS'

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{MMBD_message} = $args->{message};
    $self->{MMBD_size}    = $args->{size};
    $self;
}

sub isDelayed()   {1}
sub isMultipart() {shift->message->head->isMultipart}
sub message()     {shift->{MMBD_message}}
sub guessSize()   {shift->{MMBD_size}}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_05.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
