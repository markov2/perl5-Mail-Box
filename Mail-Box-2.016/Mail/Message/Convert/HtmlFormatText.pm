use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatText;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder;
use HTML::FormatText;

our $VERSION = 2.016;

=head1 NAME

Mail::Message::Convert::HtmlFormatText - Convert HTML into Text

=head1 CLASS HIERARCHY

 Mail::Message::Convert::HtmlFormatText
 is a Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::HtmlFormatText;
 my $af = Mail::Message::Convert::HtmlFormatText->new;

 my $plain_body = $af->format($body);

=head1 DESCRIPTION

Convert HTML/XHTML message body objects into plain text bodies
using L<HTML::FormatText>.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Convert> (MMC).

The general methods for C<Mail::Message::Convert::HtmlFormatText> objects:

   MR errors                            MR report [LEVEL]
      format BODY                       MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
   MR inGlobalDestruction              MMC selectedFields HEAD
   MR logPriority LEVEL

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION      DESCRIBED IN            DEFAULT
 fields      Mail::Message::Convert  <no used>
 leftmargin  <below>                 3
 rightmargin <below>                 72
 log         Mail::Reporter          'WARNINGS'
 trace       Mail::Reporter          'WARNINGS'

=over 4

=item * leftmargin =E<gt> INTEGER

The column of the left margin, passed to the formatter.

=item * rightmargin =E<gt> INTEGER

The column of the right margin, passed to the formatter.

=back

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCH_formatter} = HTML::FormatText->new
     ( leftmargin  => (defined $args->{leftmargin}  ? $args->{leftmargin}  : 3)
     , rightmargin => (defined $args->{rightmargin} ? $args->{rightmargin} : 72)
     );
      
    $self;
}

#------------------------------------------

=item format BODY

Pass an html/xhtml encoded body, and a plain text body is returned.
Characters are translated into Latin1.

=cut

sub format($)
{   my ($self, $body) = @_;

    my $dec  = $body->encode(transfer_encoding => 'none');
    my $tree = HTML::TreeBuilder->new_from_file($dec->file);

    (ref $body)->new
      ( based_on  => $body
      , mime_type => 'text/plain'
      , charset   => 'iso-8859-1'
      , data     => [ $self->{MMCH_formatter}->format($tree) ]
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

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
