use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatPS;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder;
use HTML::FormatText;

our $VERSION = 2.014;

=head1 NAME

Mail::Message::Convert::HtmlFormatPS - Convert HTML into PostScript

=head1 CLASS HIERARCHY

 Mail::Message::Convert::HtmlFormatPS
 is a Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::HtmlFormatPS;
 my $af = Mail::Message::Convert::HtmlFormatPS->new;

 my $postscript = $af->format($body);

=head1 DESCRIPTION

Translate an HTML/XHTML message body into a postscript body
using the L<HTML::FormatPS> package.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Convert> (MMC).

The general methods for C<Mail::Message::Convert::HtmlFormatPS> objects:

   MR errors                            MR report [LEVEL]
      format BODY                       MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Options defined by Mail::Box:

 OPTION      DESCRIBED IN            DEFAULT
 fields      Mail::Message::Convert  <no used>
 log         Mail::Reporter          'WARNINGS'
 trace       Mail::Reporter          'WARNINGS'

Furthermore, options which start with capitals are passed to
L<HTML::FormatPS> directly.  As of this writing, that package
defines
BottomMargin, FontFamily, FontScale, HorizontalMargin, Leading,
LeftMargin, PageNo, PaperHeight, PaperSize, PaperWidth, RightMargin,
TopMargin, and VerticalMargin.

=cut

sub init($)
{   my ($self, $args)  = @_;

    my @formopts = map { ($_ => delete $args->{$_} ) }
                       grep m/^[A-Z]/, keys %$args;

    $self->SUPER::init($args);

    $self->{MMCH_formatter} = HTML::FormatPS->new(@formopts);
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
      , mime_type => 'application/postscript'
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

This code is beta, version 2.014.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
