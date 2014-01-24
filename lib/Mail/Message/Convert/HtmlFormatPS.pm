use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatPS;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder;
use HTML::FormatText;

=chapter NAME

Mail::Message::Convert::HtmlFormatPS - Convert HTML into PostScript

=chapter SYNOPSIS

 use Mail::Message::Convert::HtmlFormatPS;
 my $af = Mail::Message::Convert::HtmlFormatPS->new;

 my $postscript = $af->format($body);

=chapter DESCRIPTION

Translate an HTML/XHTML message body into a postscript body
using M<HTML::FormatPS>.

=chapter METHODS

=c_method new %options

%options which start with capitals are blindly passed to M<HTML::FormatPS>.
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

=section Converting

=method format $body

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
