use strict;
use warnings;

package Mail::Message::Convert::HtmlFormatText;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;

use HTML::TreeBuilder 3.13;
use HTML::FormatText;

=head1 NAME

Mail::Message::Convert::HtmlFormatText - Convert HTML into Text

=head1 SYNOPSIS

 use Mail::Message::Convert::HtmlFormatText;
 my $af = Mail::Message::Convert::HtmlFormatText->new;

 my $plain_body = $af->format($body);

=head1 DESCRIPTION

Convert HTML/XHTML message body objects into plain text bodies
using HTML::FormatText.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=option  leftmargin INTEGER
=default leftmargin 3

The column of the left margin, passed to the formatter.

=option  rightmargin INTEGER
=default rightmargin 72

The column of the right margin, passed to the formatter.

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
      , mime_type => 'text/plain'
      , charset   => 'iso-8859-1'
      , data     => [ $self->{MMCH_formatter}->format($tree) ]
      );
}

#------------------------------------------

1;
