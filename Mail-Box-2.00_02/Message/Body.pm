package Mail::Message::Body;
use base 'Mail::Reporter';

use strict;
use warnings;
use Carp;
use Scalar::Utils;

our $VERSION = '2.00_02';

use Mail::Message;

use overload '""'  => 'string'
           , '@{}' => 'lines';

=head1 NAME

Mail::Message::Body - Contains the data of a body in a Mail::Message

=head1 SYNOPSIS

   my Mail::Message $msg = ...;
   my $body  = $msg->body;
   my @text  = $body->lines;
   my $text  = $body->string;
   my FileHandle $file = $body->file;
   $body->print(\*FILE);

=head1 DESCRIPTION

The body of a message (a Mail::Message object) is stored in one of the
body-variations.  The functionality of each body-type is equivalent, but
there are performance implications.  Each object has its own manual-page,
and you can read more specifics about those implementations in those.

=over 4

=item * Mail::Message::Body::Lines

Each line of the message-body is stored as single scalar.  This is a
useful set-up for a detailed look in the message-body, which is usually
line-organized.

=item * Mail::Message::Body::String

The whole message-body is stored in one scalar.  Small message can be
contained this way without penalty.

=item * Mail::Message::Body::File

The message body is stored in an external temporary file.  This type of
storage is especially useful when the body is large, the total folder is
large, or memory is small.

=item * Mail::Message::Body::Delayed

The message-body is not yet read-in, but the exact location of the
body is known so the message can be read when needed.

=item * Mail::Message::Body::Multipart

The message-body contains a set of sub-messages (which can contain
multiparted bodies themselves).  Each sub-message is an instance
of Mail::Message::Part, which is an extention of Mail::Message.

=item * Mail::Message::Body::External

Usually because the message body is large, the message is kept in
a seperate file.  The difference with the C<::File>-object, is
that this external storage stays this way between closing and
opening of a folder.  The C<::File>-object only use a file when
the folder is open.

=back

Each body-type has methods to produce the storage of the other types.
As example, you can ask any body-type for the message as list of lines,
but for the ::Body::Lines type this call will be most efficient.

=head1 GENERAL METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Each body-type has a few extra options, but all bodies share the
following:

=over 4

=item * message =E<gt> MESSAGE

The message where this body belongs to.

=item * data =E<gt> FILE | REF-ARRAY-OF-LINES | STRING

The content of the body can be specified in various ways.  See the
L<data> method below on how they work.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->data($args->{data}) if exists $args->{data};
    $self->message($args->{message});
    $self;
}

#------------------------------------------

=item message [MESSAGE]

Returns the message where this body belongs to, optionally setting it
to a new MESSAGE first.  If C<undef> is passed, the body will be
disconnected from the message.

=cut

sub message(;$)
{   my $self = shift;
    @_ ? weaken $self->{MMB_message} = shift : $self->{MMB_message};
}

#------------------------------------------

=item data FILE | LIST-OF-LINES | REF-ARRAY-OF-LINES | STRING

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

      !defined $arg           ? $self->_data_from_lines( [] )
    : $arg eq 'GLOB'          ? $self->_data_from_file(@_)
    : $arg->isa('IO::Handle') ? $self->_data_from_file(@_)
    : $arg eq 'ARRAY'         ? $self->_data_from_lines(@_)
    :                           $self->_data_from_lines( [@_] );
}

#
# All body implementations shall implement all of the following!!
#

sub _not_implemented($)
{   my ($self, $what) = (shift, shift);
    my $class = ref $self;
    $self->log(INTERNAL => "$class does not implement $what.");
}

sub _data_from_file(@_)  {shift->_not_implemented('reading data from file')}
sub _data_from_lines(@_) {shift->_not_implemented('reading data from lines')}

#------------------------------------------

=item string

Return the content of the body as a scalar, a single string.

BE WARNED: you will get your hands on the originals, in some types of
bodies, and you shall not change that contents!  Use the C<data()>-method
for that.

Examples:

    my $text = $body->string;
    print "Body: $body\n";     # by overloading

=cut

sub string() {shift->_not_implemented('return of body-data as string')}


#------------------------------------------

=item lines

Return the content of the body as a list of lines (in LIST-context) or
a reference to an array of lines (in SCALAR context).  Catch the body as
reference (latter possibility) may avoid needless copying, hence much
faster for large messages.

Use the C<nrLines> calls (which is usually much more efficient) to get
the number of lines in the body.

BE WARNED: you will get your hands on the originals, in some types of
bodies, and you shall not change that contents!  Use the C<data()>-method
for that.

Examples:

    my @lines    = $body->lines;     # copies lines
    my $line3    = ($body->lines)[3] # only one copy
    print $lines[0];

    my $linesref = $body->lines;     # reference to originals
    my $line3    = $body->lines->[3] # only one copy (faster)
    print $linesref->[0];

    print $body->[0];                # by overloading

=cut

sub lines() {shift->_not_implemented('return of body-data as lines')}

#------------------------------------------

=item nrLines

Returns the number of lines in the message-body.  For multi-part messages,
this includes the header-lines and boundaries of the summed parts.

=cut

sub nrLines(@_)  {shift->_not_implemented('number of lines')}

#------------------------------------------

=item size

The total number of bytes in the message-body.  Message-bodies are always
simple ascii.  The decoded message, however, may contain utf8 characters.
See the C<decode()> method of C<Mail::Message>.

=cut

sub size(@_)  {shift->_not_implemented('number of bytes')}

#------------------------------------------

=item file

Return the content of the body as a file-pointer.  The returned
stream may be a real file, or a simulated file in any form that
perl knows.  At least, you can read from it.

WARNING: Do not write to body, where some of the internal values
maintained by the C<Mail::Message::Body> may not be updated.  Use
only the C<data()> method for updates.

=cut

sub file(;$) {shift->_not_implemented('return of body-data as file')}

#------------------------------------------

=item read FILE [,LENGTH]

Read the body from the FILE. The implementation of this method will
differ from body-type to body-type.  Read the dedicated man-pages for
the specifics of each reading.

The LENGTH is the estimated number of bytes in the body, or C<undef>
when this is not known.

=cut

sub read(@) {shift->_not_implemented('reading from file')}

#------------------------------------------

=item print [FILE]

Print the body to the specified file (defaults to STDOUT)

=cut

sub print(;$) {shift->_not_implemented('printing to file')}

#------------------------------------------

=item attach MESSAGES [,OPTIONS]

Attach one or more MESSAGES to this one.  For multipart messages, this is
a simple task, but other types of message-bodies will have to be
converted into a multipart first.

=cut

sub attach(@)
{   my $self = shift;

    my @messages;
    push @messages,  shift
        while @_ && ref $_[0] && $_[0]->isa('Mail::Message');

    require Mail::Message::Construct;
    my $multi = $self->body2multipart(@_);
    $multi->addPart($_) foreach @messages;

    $self->body($multi);
    $self;
}

#------------------------------------------

=item isDelayed

Returns whether the body of this message has been taken from file.  This
is only false for a C<Mail::Message::Body::Delayed>

=cut

sub isDelayed() {0}

#------------------------------------------

=item isMultipart

Returns whether this message-body consists of multiple parts.

=cut

sub isMultipart() {0}

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
