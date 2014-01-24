use strict;
use warnings;

package Mail::Message::Wrapper::SpamAssassin;
use base 'Mail::SpamAssassin::Message';

use Carp;
use Mail::Message::Body;

BEGIN
{   my $v = $Mail::SpamAssassin::VERSION;
    die "ERROR: spam-assassin version $v is not supported (only versions 2.x)\n"
       if $v >= 3.0;
}

#------------------------------------------

=chapter NAME

Mail::Message::Wrapper::SpamAssassin - Connect a Mail::Message with Mail::SpamAssassin

=chapter SYNOPSIS

 # WARNING: requires OLD SpamAssassion 2.x, not the new 3.x
 # See Mail::Box::Search::SpamAssassin for the preferred interface
 # However, it is possible to do:

 my $msg    = ...;   # some Mail::Message object
 my $sa     = Mail::Message::Wrapper::SpamAssassin->new($msg);
 my $spam   = Mail::SpamAssassin->new;
 my $status = $spam->check($sa);

 $msg->label(spam => 1) if $status->is_spam;
 $status->rewrite_mail;  # Adds spam lines to header

=chapter DESCRIPTION

WARNING: This module only works with the old version of SpamAssassin:
version 2.x.  The newer 3.x releases have changed the way that messages
are kept. Please contribute improved code.

The C<Mail::Message::Wrapper::SpamAssassin> class --sorry for the
long package name-- is a wrapper around M<Mail::SpamAssassin::Message>, which
is an interface to the spam checking software of M<Mail::SpamAssassin>.

=chapter METHODS

=c_method new $message, %options
Creates a wrapper around the $message.  The already present fields
from a previous run of Spam::Assassin (or probably fake lines) are
removed first.

=cut

sub new(@)    # fix missing infra-structure of base element
{   my ($class, $message, %args) = @_;

    $_->delete for $message->head->spamGroups('SpamAssassin');

    $class->SUPER::new( {message => $message} )->init(\%args);
}

sub init($) { shift }

sub create_new() {croak "Should not be used"}

sub get($) { $_[0]->get_header($_[1]) }

sub get_header($)
{   my ($self, $name) = @_;
    my $head = $self->get_mail_object->head;

    # Return all fields unfolded in list context
    return map { $_->unfoldedBody } $head->get($name)
        if wantarray;

    # Only one field is expected
    my $field = $head->get($name);
    defined $field ? $field->unfoldedBody : undef;
}

sub get_pristine_header($)
{   my ($self, $name) = @_;
    my $field = $self->get_mail_object->head->get($name);
    defined $field ? $field->foldedBody : undef;
}

sub put_header($$)
{   my ($self, $name, $value) = @_;
    my $head = $self->get_mail_object->head;
    $value =~ s/\s{2,}/ /g;
    $value =~ s/\s*$//;      # will cause a refold as well
    return () unless length $value;

    $head->add($name => $value);
}

sub get_all_headers($)
{   my $head = shift->get_mail_object->head;
    "$head";
}

sub replace_header($$)
{   my $head = shift->get_mail_object->head;
    my ($name, $value) = @_;
    $head->set($name, $value);
}

sub delete_header($)
{   my $head = shift->get_mail_object->head;
    my $name = shift;
    $head->delete($name);
}

sub get_body() {shift->get_mail_object->body->lines }

sub get_pristine() { shift->get_mail_object->head->string }

sub replace_body($)
{   my ($self, $data) = @_;
    my $body = Mail::Message::Body->new(data => $data);
    $self->get_mail_object->storeBody($body);
}

sub replace_original_message($)
{   my ($self, $lines) = @_;
    die "We will not replace the message.  Use report_safe = 0\n";
}

1;
