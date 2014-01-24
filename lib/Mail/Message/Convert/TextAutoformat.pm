use strict;
use warnings;

package Mail::Message::Convert::TextAutoformat;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;
use Text::Autoformat;

=chapter NAME

Mail::Message::Convert::TextAutoformat - Reformat plain text messages

=chapter SYNOPSIS

 use Mail::Message::Convert::TextAutoformat;
 my $af = Mail::Message::Convert::TextAutoformat->new;

 my $beautified_body = $af->autoformatBody($body);

=chapter DESCRIPTION

Play trics with plain text, for instance bodies with type C<text/plain>
using Damian Conway's M<Text::Autoformat>.

=chapter METHODS

=c_method new %options

=option  options HASH-REF
=default options C<{ (all, 1) }>

Options to pass to M<Text::Autoformat>, when its C<autoformat> method
is called.

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCA_options} = $args->{autoformat} || { all => 1 };
    $self;
}

#------------------------------------------

=section Converting

=method autoformatBody $body

Formats a single message body (a M<Mail::Message::Body> object)
into a new body object using M<Text::Autoformat>.  If the
M<Text::Autoformat> is not installed, C<undef> is returned.

=cut

sub autoformatBody($)
{   my ($self, $body) = @_;

    ref($body)->new
       ( based_on => $body
       , data     => autoformat($body->string, $self->{MMCA_options})
       );
}

#------------------------------------------

1;
