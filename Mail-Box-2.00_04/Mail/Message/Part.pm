use strict;
use warnings;

package Mail::Message::Part;
use base 'Mail::Message';

our $VERSION = '2.00_04';

=head1 NAME

Mail::Message::Part - a part of a Mail::Message, but a message by itself.

=head1 SYNOPSIS

   my Mail::Message $message = ...;
   if($message->isMultipart) {

       my Mail::Message::Part $part;

       foreach $part ($message->body->parts) {
           $part->print(\*STDOUT);
           my $attachbody = $part->head;
           my $attachhead = $part->body;
       }
   }

=head1 DESCRIPTION

A C<Mail::Message::Part> object contains a message which is included in
an other message.  For instance I<attachments> are I<parts>.

READ C<Mail::Message> FIRST.  A part is a special message: it has a
reference to its parent message, and will usually not be sub-classed
into mail-folder-specific variants.

=head2 METHODS

All methods of C<Mail::Message> are available, extended by the following list.

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a message part.  You can add the following options:

 OPTIONS              DESCRIBED IN           DEFAULT
 body                 Mail::Message          <obligatory>
 head                 Mail::Message          <obligatory>
 parent               Mail::Message::Part    <obligatory>

=over 4

=item * parent =E<gt> MESSAGE

(obligatory) reference to the parental C<Mail::Message> object where this
part is a member of.  That object may be a part itself.

=back

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MM_parent} = $args{parent}
        or confess "No parent specified for part.\n";

    $self;
}

sub parent()     { shift->{MM_parent} }            # overrides
sub toplevel()   { shift->{MM_parent}->toplevel }  # idem
sub isPart()     { 1 }                             # idem

#------------------------------------------


=back

=head1 AUTHOR

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 2.00_04, so far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Message>
L<Mail::Box-Overview>

=cut

1;
