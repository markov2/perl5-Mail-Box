
use strict;

package Mail::Message::Head::Delayed;
use base 'Mail::Message::Head';

our $VERSION = '2.00_08';

use Object::Realize::Later
    becomes => 'Mail::Message::Head::Complete',
    realize => 'load';

use Carp;
use Date::Parse;

=head1 NAME

 Mail::Message::Head::Delayed - A not-read header of a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Head::Delayed realizes Mail::Message::Head::Complete
 is a Mail::Message::Head              is a Mail::Message::Head
 is a Mail::Reporter                   is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message::Head::Delayed $delayed = ...;
 $delayed->isa('Mail::Message::Head')  # true
 $delayed->guessBodySize               # undef
 $delayed->isDelayed                   # true

 See Mail::Message::Head

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box::Manager> first.

A C<Mail::Message::Head::Delayed> is used as place-holder, to be replaced
by a C<Mail::Message::Head> when someone accesses the header of a message.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head::Delayed> objects:

  MMH add ...                          MMH nrLines
  MMH clone [FIELDS]                   MMH print FILE [,LINE-LENGTH]
 MMHC count NAME                        MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MMH get NAME [,INDEX]                MMH reset NAME, FIELDS
  MMH isDelayed                        MMH set ...
  MMH isMultipart                      MMH size
   MR log [LEVEL [,STRINGS]]           MMH timestamp
  MMH names                             MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

  MMH createFromLine                    MR logPriority LEVEL
  MMH createMessageId                   MR logSettings
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH message [MESSAGE]
  MMH guessBodySize                     MR notImplemented
  MMH guessTimestamp                   MMH read PARSER
  MMH load                             MMH wrapLength [CHARS]

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMH = L<Mail::Message::Head>
 MMHC = L<Mail::Message::Head::Complete>

=head1 METHODS

=over 4

=item new OPTIONS

 OPTION      DEFINED BY              DEFAULT
 field_type  Mail::Message::Head     <not used>
 log         Mail::Reporter          'WARNINGS'
 message     Mail::Message::Head     undef
 trace       Mail::Reporter          'WARNINGS'
 wrap_length Mail::Message::Head     <not used>

No options specific to a C<Mail::Message::Head::Delayed>

=cut

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub read($)
{   my ($self, $parser, $headtype, $bodytype, $wrap)  = @_;

#   $parser->skipHeader not implemented... returns where
    $self->{MMH_where}   = 0;
    $self;
}

#------------------------------------------

sub load() {shift->message->loadHead}

#------------------------------------------

sub guessBodySize() {undef}

#-------------------------------------------

sub guessTimestamp() {undef}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_08.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
