use strict;
use warnings;

package Mail::Message;
use base 'Mail::Reporter';

use Mail::Message::Part;
use Carp;

our $VERSION = '2.00_02';

=head1 NAME

Mail::Message - basic message object

=head1 SYNOPSIS

  use Mail::Box::Manager;
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open(folder => $MAIL);
  my $msg    = $folder->message(2);    # $msg isa Mail::Message

  my Mail::Message $construct  = Mail::Message->new;
  my Mail::Message::Head $head = $msg->head;
  my Mail::Message::Body $body = $msg->body;

=head1 DESCRIPTION

A C<Mail::Message> object is a container for message information read from a
file.  All implemention is contained in sub-classes, most probably
in C<Mail::Box::Message>.

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

Instantiate the message with a body which has been created somewhere
before the message is constructed.  The OBJECT must be a sub-class
of C<Mail::Message::Body>.

=item * head =E<gt> OBJECT

Instantiate the message with a head which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of C<Mail::Message::Head>.

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

=item parent

=item isPart

=item toplevel

If the message is a part of another message, C<parent> returns the reference
to the containing message. C<parent> returns C<undef> if the message is not a
part, but rather the main message.  C<isPart> returns true if the message
is a part of another message.  C<toplevel> returns a reference to the main
message, which will be the current message if the message is not part of
another message.

Examples:

    my $msg    = $parser->read;

    return unless $msg->body->isa('Mail::Message::Body::Multipart');
    my $part   = $msg->body->part(2);

    return unless $part->body->isa('Mail::Message::Body::Multipart');
    my $nested = $part->body->part(3);

    $nested->parent;     # returns $part
    $nested->toplevel;   # returns $msg
    $msg->parent;        # returns undef
    $msg->toplevel;      # returns $msg
    $msg->isPart;        # returns false
    $part->isPart;       # returns true

=cut

sub parent()     { undef }   # overridden by Mail::Message::Part
sub toplevel()   { shift }   # idem
sub isPart()     { 0 }       # idem

#------------------------------------------

=item body [OBJECT]

=item head [OBJECT]

Return (optionally after setting) the body/head of this message.

The OBJECT must be an (sub-)class of C<Mail::Message::Body> or
C<Mail::Message::Head> respectively.  Setting the body is usually done
C<Mail::Box> sub-classes, and not by user programs.

Examples:

    $msg->body->print(\*STDERR);
    print STDERR $msg->body;       # same
    $msg->body(Mail::Message::Body::Lines->new);
    my $head = $msg->head(new Mail::Message::Head);

=cut
  
sub body(;$)
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my $body = shift;
    confess "Internal error: wrong type of body for $_[0]"
        unless ref $body && $body->isa('Mail::Message::Body');

    $body->message($self);
    $self->{MM_body} = $body;
}

sub head(;$)
{   my $self   = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    die "Internal error: wrong type of head for $_[0]"
        unless ref $head && $head->isa('Mail::Message::Head');

    $head->message($self);
    $self->{MM_head} = $head;
}

#-------------------------------------------

=item guessTimestamp

Return an estimate on the time this message was sent.  The data is
derived from the header, where it can be derived from the C<date> and
C<received> lines.  For MBox-like folders you may get the date from
the from-line as well.

This method may return C<undef> if the header is not parsed or only
partially known.  If you require a time, then use the C<timestamp()>
method, described below.

Examples:

    print "Receipt ", ($message->timestamp || 'unknown'), "\n";

=cut

sub guessTimestamp() {shift->head->guessTimestamp}

#-------------------------------------------

=item timestamp

Get a timestamp, doesn't matter how much work it is.  If it is impossible
to get a time from the header-lines, the current time-of-living is taken.

=cut

sub timestamp() {shift->head->load->guessTimestamp || time}

#-------------------------------------------

=item isDelayed

C<isDelayed> checks whether the message is delayed (not yet read from file).
Returns true or false.  For this, it checks the body-type.

=cut

sub isDelayed() {shift->body->isDelayed}

#------------------------------------------

=item isDummy

Dummy messages are used to fill holes in linked-list and such, where only
a message-id is known, but not the place of the header of body data.

This method is also available for C<Mail::Message::Dummy> objects, where
this will return C<true>.  On any extention of C<Mail::Message>, this will
return C<false>.

=cut

sub isDummy()    { 0 }

#------------------------------------------

=item isMultipart

Check whether this message is a multipart message (has attachments).  To
find this out, we need at least the header of the message; there is no
need to read the body of the message to detect this.

=cut

sub isMultipart() {shift->body->isMultipart}

#------------------------------------------
# All next routines try to create compatibility with release < 2.0

sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#-------------------------------------------
# Next routines try to create compatibility with Mail::Internet and
# MIME::Entity

sub bodyhandle()
{   my $self = shift;
    $self->isMultipart ? undef : $self->body->decoded;
}

sub parts(;$)   # optional index
{   my $self = shift;

      ! $self->isMultipart ? ()
    : ! @_                 ? $self->body->parts
    :                        $self->body->part(shift);
}

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 2.00_02, so far from complete.  Please
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
