package Mail::Message::Body;

use strict;
use warnings;
use Carp;

our $VERSION = '1.315';

use Mail::Message;

=head1 NAME

Mail::Message::Body - UNDER CONSTRUCTION: Contains the data of a body in a Mail::Message

=head1 SYNOPSIS

   my Mail::Message $msg = ...;
   my $body  = $msg->body;
   my @lines = $body->lines;
   my $text  = $body->string;
   my FileHandle $file = $body->file;
   $body->write(\*FILE);

=head1 DESCRIPTION

The body of a message (a Mail::Message object) is stored in one of the
body-variations.  The fuctionality of each body-type is equivalent, but
there are performance implications.

=over 4

=item * Mail::Message::Body::Lines

Each line of the message-body is stored as single scalar.  This is a
useful set-up for a detailed look in the message-body, which is usually
line-organized.

=item * Mail::Message::Body::Scalar

The whole message-body is stored in one scalar.  Small message can be
contained this way without penalty.

=item * Mail::Message::Body::File

The message body is stored in an external temporary file.  This type of
storage is especially useful when the body is large, the total folder is
large, or memory is small.

=item * Mail::Message::Body::NotParsed

The message-body is not yet read-in, but the exact location of the
body is known so the message can be read when needed.

=item * Mail::Message::Body::Multipart

The message-body contains a set of sub-messages (which can contain
multiparted bodies themselves).  Each sub-message is an instance
of Mail::Message::Part, which is an extention of Mail::Message.

=back

Each body-type has methods to produce the storage of the other types.
As example, you can ask any body-type for the message as list of lines,
but for the ::Body::Lines type this call will be most efficient.

=head1 GENERAL METHODS

=cut

#------------------------------------------

=item new OPTIONS

Each body-type has a few extra options, but all bodies share the
following:

=over 4

=item * data =E<gt> FILE | REF-ARRAY-OF-LINES | SCALAR

The content of the body can be specified in various ways.  See the
L<data> method below on how they work.

=back

=cut

sub new()
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    $self->data($args{data}) if exists $args{data};
    $self;
}

#------------------------------------------

=item data FILE | LIST-OF-LINES | REF-ARRAY-OF-LINES | SCALAR

Store the specified data as body, replacing the old content.

Dependent on the type of body and the type of data supplied, this may be
little work or a lot of work. 

Examples:

   my $body = Mail::Message::Body::Lines->new;
   $body->data(\*INBOX);
   $body->data("first line", $second_line);
   $body->data( ["first line", $second_line] );
   $body->data("first line\n$second_line\n");

=cut

sub data(@)
{   my $self = shift;
    my $arg  = defined $_[0] ? ref $_[0] : undef;

      $arg eq 'GLOB'  ? $self->_data_from_file(@_)
    : $arg eq 'ARRAY' ? $self->_data_from_lines(@_)
    : !defined $arg   ? $self->_data_from_lines( [] )
    :                   $self->_data_from_lines( [@_] );
}

#
# All body implementations shall implement all of the following!!
#

sub _not_implemented($)
{   my ($class, $what) = (ref shift, shift);
    confess "$class does not implement $what.\n";
}

sub _data_from_file(@_)  {shift->_not_implemented('reading data from file')}
sub _data_from_lines(@_) {shift->_not_implemented('reading data from lines')}

#------------------------------------------

=item scalar

Return the content of the body as a scalar.

=cut

#------------------------------------------

=item lines

Return the content of the body as a list of lines.

=cut

#------------------------------------------

=item file

Return the content of the body as a file-pointer.  The returned
stream may be a real file, or a simulated file in any form that
perl knows.  At least, you can read from it.

=cut

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 1.313, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Box::Manager>

=cut

1;
