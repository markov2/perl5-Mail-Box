use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatPS;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder;
use HTML::FormatText;

=head1 NAME

Mail::Message::Convert::HtmlFormatPS - Convert HTML into PostScript

=head1 SYNOPSIS

 use Mail::Message::Convert::HtmlFormatPS;
 my $af = Mail::Message::Convert::HtmlFormatPS->new;

 my $postscript = $af->format($body);

=head1 DESCRIPTION

Translate an HTML/XHTML message body into a postscript body
using HTML::FormatPS.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

OPTIONS which start with capitals are blindly passed to HTML::FormatPS.
As of this writing, that package
defines BottomMargin, FontFamily, FontScale, HorizontalMargin, Leading,
LeftMargin, PageNo, PaperHeight, PaperSize, PaperWidth, RightMargin,
TopMargin, and VerticalMargin.

=default fields <not used>

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

=head2 Converting

=cut

#------------------------------------------

=method format BODY

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

1;
