package Mail::Message::Body;
use base 'Mail::Reporter';

use strict;
use warnings;
use Carp;

our $VERSION = '2.00_07';

use overload '""'  => 'string'
           , '@{}' => 'lines';

use Scalar::Util 'weaken';

=head1 NAME

 Mail::Message::Body - the data of a body in a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Body
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $body  = $msg->body;
 my @text  = $body->lines;
 my $text  = $body->string;
 my FileHandle $file = $body->file;
 $body->print(\*FILE);
 $body->attach(new Mail::Message::Part);

=head1 DESCRIPTION

The body of a message (a C<Mail::Message> object) is stored in one of the
body types.  The functionality of each body type is equivalent, but there
are performance differences.  Each body type has its own documentation
which contains details about its implementation.

=over 4

=item * C<Mail::Message::Body::Lines>

Each line of the message body is stored as single scalar.  This is a
useful representation for a detailed look in the message body, which is
usually line-organized.

=item * C<Mail::Message::Body::String>

The whole message body is stored in one scalar.  Small messages can be
contained this way without performance penalties.

=item * C<Mail::Message::Body::File>

The message body is stored in an external temporary file.  This type of
storage is especially useful when the body is large, the total folder is
large, or memory is limited.

=item * C<Mail::Message::Body::Delayed>

The message-body is not yet read, but the exact location of the
body is known so the message can be read when needed.

=item * C<Mail::Message::Body::Multipart>

The message body contains a set of sub-messages (which can contain
multipart bodies themselves).  Each sub-message is an instance
of C<Mail::Message::Part>, which is an extension of C<Mail::Message>.

=item * C<Mail::Message::Body::External>

The message is kept in a separate file, usually because the message body
is large.  The difference with the C<::External> object is that this external
storage stays this way between closing and opening of a folder. The
C<::External> object only uses a file when the folder is open.

=back

Each body type has methods to produce the storage of the other types.
As example, you can ask any body type for the message as a list of lines,
but this call will be most efficient for the C<::Body::Lines> type.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body> objects:

      clone                                nrLines
      data FILE | LIST-OF-LINES |...       print [FILE]
   MR errors                               reply OPTIONS
      file                              MR report [LEVEL]
      isDelayed                         MR reportAll [LEVEL]
      isMultipart                          size
      lines                                string
   MR log [LEVEL [,STRINGS]]               stripSignature OPTIONS
      message [MESSAGE]                 MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

      load                              MR notImplemented
   MR logPriority LEVEL                    read PARSER [,CHARS [,LINES]]
   MR logSettings                          start

Prefixed methods are descibed in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Each body type has a few extra options, but all bodies share the
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
    $self->SUPER::init($args);
    $self->data($args->{data}) if exists $args->{data};
    $self->message($args->{message});
    $self;
}

#------------------------------------------

=item clone

Return a copy of this body, usually to be included in a cloned
message (see C<Mail::Message::clone>).

=cut

sub clone() {shift->notImplemented}

#------------------------------------------

=item message [MESSAGE]

Returns the message where this body belongs to, optionally setting it
to a new MESSAGE first.  If C<undef> is passed, the body will be
disconnected from the message.

=cut

sub message(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MMB_message} = shift;
        weaken $self->{MMB_message};
    }
    $self->{MMB_message};
}

#------------------------------------------

=item data FILE | LIST-OF-LINES | REF-ARRAY-OF-LINES | STRING

Store the specified data as the body, replacing the old content.

Depending on the type of body and the type of data supplied, this may be
a little work or a lot of work.

Examples:

   my $body = Mail::Message::Body::Lines->new;
   $body->data(\*INBOX);
   $body->data("first line", $second_line);
   $body->data( ["first line", $second_line] );
   $body->data("first line\n$second_line\n");

=cut

# Not to be extended.

sub data(@)
{   my $self = shift;

    my $type  = defined $_[0]  ? ref $_[0] : undef;

      !defined $type           ? $self->_data_from_lines( [] )
    : !$type                   ? $self->_data_from_lines( [@_] )
    : $type eq 'GLOB'          ? $self->_data_from_file(@_)
    : $type eq 'ARRAY'         ? $self->_data_from_lines(@_)
    : $type->isa('IO::Handle') ? $self->_data_from_file(@_)
    : confess;
}

# All body implementations shall implement all of the following!!

sub _data_from_file(@_)  {shift->notImplemented}
sub _data_from_lines(@_) {shift->notImplemented}

#------------------------------------------

=item string

Return the content of the body as a scalar (a single string).  This is
a copy of the internally kept information.

Examples:

    my $text = $body->string;
    print "Body: $body\n";     # by overloading

=cut

sub string() {shift->notImplemented}


#------------------------------------------

=item lines

Return the content of the body as a list of lines (in LIST context) or a
reference to an array of lines (in SCALAR context).  In scalar context the
array of lines is cached to avoid needless copying and therefore provide
much faster access for large messages.

To just get the number of lines in the body, use the C<nrLines> method,
which is usually much more efficient.

BE WARNED: For some types of bodies the reference will refer to the
original data. You must not change the referenced data! If you do some of
the internal values maintained by the C<Mail::Message::Body> may not be
updated.   Use the C<data()> method instead.

Examples:

    my @lines    = $body->lines;     # copies lines
    my $line3    = ($body->lines)[3] # only one copy
    print $lines[0];

    my $linesref = $body->lines;     # reference to originals
    my $line3    = $body->lines->[3] # only one copy (faster)
    print $linesref->[0];

    print $body->[0];                # by overloading

=cut

sub lines() {shift->notImplemented}

#------------------------------------------

=item file

Return the content of the body as a file handle.  The returned stream may
be a real file, or a simulated file in any form that Perl supports.  While
you may not be able to write to the file handle, you can read from it.

WARNING: Even if the file handle supports writing, do not write to the
file handle. If you do some of the internal values maintained by the
C<Mail::Message::Body> may not be updated.  Use only the C<data()> method
instead.

=cut

sub file(;$) {shift->notImplemented}

#------------------------------------------

=item nrLines

Returns the number of lines in the message body.  For multi-part messages,
this includes the header lines and boundaries of all the parts.

=cut

sub nrLines(@_)  {shift->notImplemented}

#------------------------------------------

=item size

The estimate total number of bytes in the message body.  Message bodies
are always simple ASCII.  The decoded message, however, may contain UTF8
characters.  See the C<decode()> method of C<Mail::Message>.

=cut

sub size(@_)  {shift->notImplemented}

#------------------------------------------

=item print [FILE]

Print the body to the specified file (defaults to STDOUT)

=cut

sub print(;$) {shift->notImplemented}

#------------------------------------------

=item reply OPTIONS

Create a basic reply message to the content of this body.  See
C<Mail::Message::Construct::reply()> for details and the OPTIONS.

=cut

sub reply(@) {shift->message->reply(@_)}

#------------------------------------------

=item stripSignature OPTIONS

Remove a signature from this body of the message.  The lines of the
signature are returned.  See C<Mail::Message::Construct::stripSignature()>
for details and OPTIONS.

=cut

sub stripSignature(@) {shift->message->stripSignature(@_)}

#------------------------------------------

=item isDelayed

Returns a true or false value, depending on whether the body of this
message has been read from file.  This can only false for a
C<Mail::Message::Body::Delayed>.

=cut

sub isDelayed() {0}

#------------------------------------------

=item isMultipart

Returns whether this message-body consists of multiple parts.

=cut

sub isMultipart() {0}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item read PARSER [,CHARS [,LINES]]

Read the body with the PARSER from file. The implementation of this method
will differ from body type to body type.

The CHARS argument is the estimated number of bytes in the body, or
C<undef> when this is not known.  This data can sometimes be derived from
the header (the C<Content-Length> line) or file-size.

The second argument is the estimated number of LINES of the body.  It is less
useful than the CHARS but may be of help determining whether the message
separator is trustworthy.  This value may be found in the C<Lines> field
of the header.

=cut

sub read(@) {shift->notImplemented}

#------------------------------------------

=item start

First byte of the body in the file.

=cut

sub start() {shift->{MMH_where}}

#------------------------------------------

=item load

Be sure that the body is loaded.  This returns the loaded body.

=cut

sub load() {shift}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_07.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
