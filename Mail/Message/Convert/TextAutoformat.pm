use strict;
use warnings;

package Mail::Message::Convert::TextAutoformat;
use base 'Mail::Message::Convert';

use Mail::Message::Body::String;
use Text::Autoformat;

=head1 NAME

Mail::Message::Convert::TextAutoformat - Reformat plain text messages

=head1 SYNOPSIS

 use Mail::Message::Convert::TextAutoformat;
 my $af = Mail::Message::Convert::TextAutoformat->new;

 my $beautified_body = $af->autoformatBody($body);

=head1 DESCRIPTION

Play trics with plain text, for instance bodies with type C<text/plain>
using Damian Conways Text::Autoformat.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

=option  options HASH-REF
=default options { all => 1 }

Options to pass to Text::Autoformat, when its C<autoformat> method
is called.

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    $self->{MMCA_options} = $args->{autoformat} || { all => 1 };
    $self;
}

#------------------------------------------

=head2 Converting

=cut

#------------------------------------------

=method autoformatBody BODY

Formats a single message body (a Mail::Message::Body object)
into a new body object using Text::Autoformat.  If the
Text::Autoformat is not installed, C<undef> is returned.

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
