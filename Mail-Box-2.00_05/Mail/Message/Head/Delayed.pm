
use strict;

package Mail::Message::Head::Delayed;
use base 'Mail::Message::Head';

our $VERSION = '2.00_05';

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

  MMH add NAME, BODY [,COMMENT]        MMH message [MESSAGE]
  MMH clone [FIELDS]                   MMH names
  MMH count NAME                           new OPTIONS
  MMH createFromLine                   MMH new OPTIONS
  MMH createMessageId                 MMHC new OPTIONS
   MR errors                            MR new OPTIONS
  MMH get NAME [,INDEX]                MMH print FILE [,LINE-LENGTH]
  MMH grepNames [NAMES|ARRAY-OF-N...    MR report [LEVEL]
  MMH guessBodySize                     MR reportAll [LEVEL]
  MMH guessTimestamp                   MMH reset NAME, FIELDS
  MMH isDelayed                        MMH set NAME, BODY [,COMMENT]
  MMH isMultipart                      MMH timestamp
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

  MMH load                              MR notImplemented
   MR logPriority LEVEL                MMH read PARSER

Methods prefixed with an abbreviation are described in the following
manual-pages:

    MR = L<Mail::Reporter>
   MMH = L<Mail::Message::Head>
  MMHC = L<Mail::Message::Head::Complete>


=head1 METHODS

=head1 METHODS
=over 4

=item new OPTIONS

 OPTION         DEFINED BY             DEFAULT
 complete_type  Mail::Message::Head    'Mail::Message::Head::Complete'
 field_type     Mail::Message::Head    'Mail::Message::Field'
 log            Mail::Reporter         'WARNINGS'
 message        Mail::Message::Head    undef
 trace          Mail::Reporter         'WARNINGS'

No options specific to a C<Mail::Message::Head::Delayed>

=cut

#-------------------------------------------

sub guessBodySize() {undef}

sub guessTimestamp() {undef}

#------------------------------------------

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
