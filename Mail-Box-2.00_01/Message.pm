use strict;
use warnings;

package Mail::Message;

use base 'Mail::Reporter';
use Mail::Message::Part;

our $VERSION = '2.00_01';

=head1 NAME

Mail::Message - basic message object

=head1 SYNOPSIS

  use Mail::Box::Manager;
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open(folder => $MAIL);
  my $msg    = $folder->message(2);    # isa Mail::Message

  my Mail::Message $construct  = Mail::Message->new;
  my Mail::Message::Head $head = $msg->head;
  my Mail::Message::Body $body = $msg->body;

=head1 DESCRIPTION

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

 body              Mail::Message      undef
 head              Mail::Message      undef
 log               Mail::Reporter     'WARNINGS'
 trace             Mail::Reporter     'WARNINGS'

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

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

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
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my $body = shift;
    die "Internal error: wrong type of body for $_[0]"
        unless ref $body && $body->isa('Mail::Message::Body');

    $self->{MM_body} = $body;
}

sub head(;$)
{   my $self   = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    die "Internal error: wrong type of head for $_[0]"
        unless ref $head && $head->isa('Mail::Message::Head');

    $self->{MM_head} = $head;
}

#-------------------------------------------

=item isDelayed

C<isDelayed> checks whether the message is delayed (not yet read from file).
Returns true or false.  For this, it checks the body-type.

=cut

sub isDelayed()
{   my $self = shift;
    !defined $self->{MM_body} || $self->{MM_body}->isDelayed;
}

sub isParsed()  { shift->isDelayed }  # compatibility with release < 2.0

#------------------------------------------

=item headIsDelayed

Checks if the head of the message is read.

=cut

sub headIsDelayed()
{   my $self = shift;
    !defined $self->{MM_head} || $self->{MM_head}->isDelayed;
}

sub headIsRead() { not shift->headIsDelayed } # compatibility

#-------------------------------------------

=item isDummy

C<isDummy> Checks whether the message is only found in a thread, but
not (yet) in the folder.  Only a C<Mail::Message::Dummy> will
return true.

=cut

sub isDummy() { 0 }

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 1.318, so far from complete.  Please
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
