package Mail::Message;

use strict;
use warnings;

our $VERSION = '1.313';

use Mail::Box;

=head1 NAME

Mail::Message - UNDER CONSTRUCTION: new basic message object

=head1 SYNOPSIS

  use Mail::Box::Manager;
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open(folder => $MAIL);
  my $msg    = $folder->message(2);    # isa Mail::Message

  my Mail::Message $reply      = $msg->reply;
  my Mail::Message $construct  = Mail::Message->new;
  my Mail::Message::Head $head = $msg->head;
  my Mail::Message::Body $body = $msg->body;

  This manual also describes Mail::Message::Part

=head1 DESCRIPTION Mail::Message

A Mail::Message object is a container for information read from a
file.  All intelligence is implemented by sub-classes, most probably
by Mail::Box::Message.


=head2 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message object.  The message's head and body will
be read later, unless specified at construction.

=over 4

=item * body =E<gt> OBJECT

Instantiate the message with a body, which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of Mail::Message::Body.

=item * head =E<gt> OBJECT

Instantiate the message with a head, which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of Mail::Message::Head.

=back

=cut

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->body($args->{body}) if $args->{body};
    $self->head($args->{head}) if $args->{head};

    $self;
}

#------------------------------------------

=item errors

=item warnings

Returns a list with all errors/warnings found while processing this message.
Examples:

   my @errors = $msg->errors;
   if($msg->errors || $msg->warnings) {...};

=cut

sub errors()
{   my $self = shift;
    $self->{MM_fh}->report(ERRORS => $self);
}

sub warnings()
{   my $self = shift;
    $self->{MM_fh}->report(WARNINGS => $self);
}

#------------------------------------------

=item parent

=item isToplevel

=item toplevel

C<parent> returns the reference to the message where this a part of, and
C<undef> if it is not a part, but the main message.  The C<isToplevel>
returns true, only in the latter case.  With C<toplevel>, you get the
main message (maybe the current message).

Examples:

    my $msg    = $fh->read;
    my $part   = $msg->part(2);
    my $nested = $part->part(3);

    $nested->parent;     # returns $part
    $nested->toplevel;   # returns $msg
    $msg->parent;        # returns undef
    $msg->toplevel;      # returns $msg
    $msg->isToplevel;    # returns true

=cut

sub parent()     { undef }   # overridden by Mail::Message::Part
sub toplevel()   { shift }   # idem
sub isToplevel() { 1 }       # idem

#------------------------------------------

=item body [OBJECT]

=item head [OBJECT]

Return (optionally after setting) the body/head of this message.

The OBJECT must be an (sub-)class of Mail::Message::Body respectively
Mail::Message::Head.  However, setting the body is a task of
Mail::Box-derivates, and not a usual practice for user programs.

Examples:

    $msg->body->print(\*STDERR);
    $msg->body(Mail::Message::Body::Lines->new);
    my $head = $msg->head(new Mail::Message::Head);

=cut
  
sub body(;$)
{   my $sel = shift;
    return $self->{MB_body} unless @_;

    my $body = shift;
    die "Internal error: wrong type of body for $_[0]"
        unless ref $body && $body->isa('Mail::Message::Body');

    $self->{MB_body} = $body;
}

sub head(;$)
{   my $self   = shift;
    return $self->{MB_head} unless @_;

    my $head = shift;
    die "Internal error: wrong type of head for $_[0]"
        unless ref $head && $head->isa('Mail::Message::Head');

    $self->{MB_head} = $head;
}

#------------------------------------------

package Mail::Message::Part;
our @ISA = qw(Mail::Message);

=head1 DESCRIPTION Mail::Message::Part

A message may have a multipart body, in which case the main message
contains many sub-messages (parts).  These parts may be multipart
messages by themselves.

The methods available for the parts are the same as for the main
messages.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MM_parent} = $args{parent}
        or die "Internal error: no parent specified for part.\n";

    $self;
}

sub parent()     { shift->{MM_parent} }            # overrides
sub toplevel()   { shift->{MM_parent}->toplevel }  # idem
sub isToplevel() { 0 }                             # idem

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>
David Coppit <david@coppit.org>

=head1 VERSION

This code is beta version 1.313, so far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer and David Coppit. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Box>
L<Mail::Folder::FastReader>

=cut

1;
