use strict;
use warnings;

package Mail::Message::Convert::TextAutoformat;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;
use Text::Autoformat;

our $VERSION = 2.017;

=head1 NAME

Mail::Message::Convert::TextAutoformat - Reformat plain text messages

=head1 CLASS HIERARCHY

 Mail::Message::Convert::TextAutoformat
 is a Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::TextAutoformat;
 my $af = Mail::Message::Convert::TextAutoformat->new;

 my $beautified_body = $af->autoformatBody($body);

=head1 DESCRIPTION

Play trics with plain text, for instance bodies with type C<text/plain>
using Damian Conways L<Text::Autoformat>.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Convert> (MMC).

The general methods for C<Mail::Message::Convert::TextAutoformat> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                       MR warnings
   MR report [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
      autoformatBody BODY               MR notImplemented
   MR inGlobalDestruction              MMC selectedFields HEAD

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION      DESCRIBED IN            DEFAULT
 options     M::M::C::TextAutoformat { all => 1 }
 log         Mail::Reporter          'WARNINGS'
 trace       Mail::Reporter          'WARNINGS'

=over 4

=item * options =E<gt> HASH-REF

Options to pass to L<Text::Autoformat>, when its C<autoformat> method
is called.

=back

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCA_options} = $args->{autoformat} || { all => 1 };
    $self;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item autoformatBody BODY

Formats a single message body (a C<Mail::Message::Body> object)
into a new body object using C<Text::Autoformat>.  If the
C<Text::Autoformat> is not installed, C<undef> is returned.

=cut

sub autoformatBody($)
{   my ($self, $body) = @_;

    ref($body)->new
       ( based_on => $body
       , data     => autoformat($body->string, $self->{MMCA_options})
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

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
