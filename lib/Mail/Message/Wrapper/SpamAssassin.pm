use strict;
use warnings;

package Mail::Message::Wrapper::SpamAssassin;
use base 'Mail::SpamAssassin::Message';

use Carp;
use Mail::Message::Body::Lines;

#------------------------------------------

=chapter NAME

Mail::Message::Wrapper::SpamAssassin - Connect a Mail::Message with Mail::SpamAssassin

=chapter SYNOPSIS

 # See Mail::Box::Search::SpamAssassin for the prefered interface
 # However, it is possible to do:

 my $msg    = ...;   # some Mail::Message object
 my $sa     = Mail::Message::Wrapper::SpamAssassin->new($msg);
 my $spam   = Mail::SpamAssassin->new;
 my $status = $spam->check($sa);

 $msg->label(spam => 1) if $status->is_spam;
 $status->rewrite_mail;  # Adds spam lines to header

=chapter DESCRIPTION

The C<Mail::Message::Wrapper::SpamAssassin>
class --sorry for the long package
name-- is a wrapper around M<Mail::SpamAssassin::Message>, which is an
interface to the spam checking software of M<Mail::SpamAssassin>.

=chapter METHODS

=c_method new MESSAGE, OPTIONS

Creates a wrapper around the MESSAGE.

=cut

sub new(@)
{   my ($class, $message, %args) = @_;
    $class->SUPER::new($message)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    $self;
}

#------------------------------------------

sub create_new() {croak "Should not be used"}

#------------------------------------------

sub get($) { $_[0]->get_header($_[1]) }

sub get_header($)
{   my ($self, $name) = @_;
    my $field = $self->get_mail_object->head->get($name);
    defined $field ? $field->unfoldedBody : undef;
}

#------------------------------------------

sub put_header($$)
{   my ($self, $name, $value) = @_;
    my $head = $self->get_mail_object->head;
    $value =~ s/\s{2,}/ /g;
    return if $value =~ s/^\s*$//;
    $head->add($name => $value);
}

#------------------------------------------

sub get_all_headers($)
{   my $head = shift->get_mail_object->head;
    "$head";
}
    
#------------------------------------------

sub replace_header($$)
{   my $head = shift->get_mail_object->head;
    my ($name, $value) = @_;
    $head->set($name, $value);
}

#------------------------------------------

sub delete_header($)
{   my $head = shift->get_mail_object->head;
    my $name = shift;
    $head->delete($name);
}

#------------------------------------------

sub get_body() {shift->get_mail_object->body->lines }

#------------------------------------------

sub replace_body($)
{   my ($self, $data) = @_;
    my $body = Mail::Message::Body::Lines->new(data => $data);
    $self->get_mail_object->storeBody($body);
}

#------------------------------------------

1;
