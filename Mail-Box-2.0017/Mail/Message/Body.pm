use strict;
use warnings;

package Mail::Message::Body;
use base 'Mail::Reporter';

use Mail::Message::Field;

our $VERSION = 2.00_17;

use overload bool  => sub {1}   # $body->print if $body
           , '""'  => 'string'
           , '@{}' => 'lines'
           , '=='  => sub {$_[0]->{MMB_seqnr}==$_[1]->{MMB_seqnr}}
           , '!='  => sub {$_[0]->{MMB_seqnr}!=$_[1]->{MMB_seqnr}};

use Carp;
use Scalar::Util 'weaken';
use FileHandle;

use MIME::Types;
my $mime_types = MIME::Types->new;

=head1 NAME

Mail::Message::Body - the data of a body in a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Body + ::Construct + ::Encode
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $body  = $msg->body;
 my @text  = $body->lines;
 my $text  = $body->string;
 my FileHandle $file = $body->file;
 $body->print(\*FILE);

 my $content_type = $body->type;
 my $transfer_encoding = $body->transferEncoding;
 my $encoded  = $body->encode(mime_type => 'text/html',
    charset => 'us-ascii', transfer_encoding => 'NONE');
 my $decoded  = $body->decoded;

=head1 DESCRIPTION

The encoding and decoding functionality of a C<Mail::Message::Body> is
implemented in the C<Mail::Message::Body::Encode> package.  That package is
automatically loaded when encoding and decoding of messages needs to take
place.

The body of a message (a C<Mail::Message> object) is stored in one of the
body types.  The functionality of each body type is equivalent, but there
are performance differences.  Each body type has its own documentation
which contains details about its implementation.

A body can be contained in a message, but may also live without a message.
In both cases it stores data, and the same questions can be asked: what
type of data it is, how many bytes and lines, what encoding is used.  Any
body can be encoded and decoded, returning a new body object.  However, 
bodies which are part of a message will always be in a shape that they can
be written to a file or send to somewhere: they will be encoded if needed.

For example:

 my $body    = Mail::Message::Body::String->new(mime_type => 'image/gif');
 $body->print(\*OUT);    # this is binary image data...

 my $encoded = $message->body($body);
 $encoded->print(\*OUT); # ascii data, encoded image

Now encoded refers to the body of the C<$message> which is the content of
C<$body> in a shape that it can be transmitted.  Usually C<base64> encoding
is used.
  
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

=item * C<Mail::Message::Body::InFolder>

NOT IMPLEMENTED YET.
The message is kept in the folder, and is only taken out when the
content is changed.

=item * C<Mail::Message::Body::External>

NOT IMPLEMENTED YET.
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

 MMBC attach MESSAGES, OPTIONS             message [MESSAGE]
 MMBE check                                mimeType
      checked [BOOLEAN]                    modified [BOOL]
 MMBC concatenate COMPONENTS               new OPTIONS
      decoded OPTIONS                      nrLines
      disposition [STRING|FIELD]           print [FILE]
 MMBE encode OPTIONS                       reply OPTIONS
 MMBE encoded                           MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
      file                                 size
 MMBC foreachLine CODE                     string
 MMBE isBinary                        MMBC stripSignature OPTIONS
      isDelayed                         MR trace [LEVEL]
      isMultipart                          transferEncoding [STRING|FI...
      lines                                type
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                             load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
      clone                                moveLocation [DISTANCE]
      fileLocation                      MR notImplemented
 MMBE getTransferEncHandler TYPE           read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction             MMBE unify BODY

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
 MMBC = L<Mail::Message::Body::Construct>
 MMBE = L<Mail::Message::Body::Encode>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN          DEFAULT
 based_on          Mail::Message::Body   undef
 charset           Mail::Message::Body   'us-ascii'
 checked           Mail::Message::Body   0
 data              Mail::Message::Body   undef
 disposition       Mail::Message::Body   undef
 filename          Mail::Message::Body   undef
 log               Mail::Reporter        'WARNINGS'
 message           Mail::Message::Body   undef
 mime_type         Mail::Message::Body   'text/plain'
 modified          Mail::Message::Body   0
 trace             Mail::Reporter        'WARNINGS'
 transfer_encoding Mail::Message::Body   'NONE'

=over 4

=item * based_on =E<gt> BODY

The information about encodings must be taken from the specified BODY,
unless specified differently.

=item * charset =E<gt> STRING

Defines the character-set which is used in the data.  Only useful in
conbination with a C<mime_type> which refers to C<text> in any shape.
This field is case-insensitive.

=item * checked =E<gt> BOOLEAN

Whether the added information has been check not to contain illegal
octets with respect to the transfer encoding and mime type.  If not
checked, and then set as body for a message, it will be.

=item * data =E<gt> | ARRAY-OF-LINES | STRING

The content of the body.  The only way to set the content of a body
is during the creation of the body.  So if you want to modify the content
of a message, you need to create a new body with the new content and
add that to the body.  The reason behind this, is that correct encodings
and body information must be guaranteed.  It avoids your hassle in
calculating the number of lines in the body, and checking whether bad
characters are enclosed in text.

Specify a reference to an ARRAY of lines, each terminated by a newline.
Or one STRING which may contain multiple lines, seperated and terminated
by a newline.

=item * disposition =E<gt> STRING|FIELD

How this message can be decomposed.  The data relates to the
C<Content-Disposition> field.  Specify a STRING which will become the
field content, or a real FIELD.

The content of this field is specified in RFC 1806.  The body of the
field can be C<inline>, to indicate that the body is intended to be
displayed automatically upon display of the message. Use C<attachment>
to indicate that they are separate from the main body of the mail
message, and that their display should not be automatic, but contingent
upon some further action of the user.

The C<filename> attribute specifies a name to which is suggested to the
reader of the message when it is extacted.

=item * file =E<gt> FILENAME|FILEHANDLE|IOHANDLE

Read the data from the specified file, file handle, or object of
type C<IO::Handle>.

=item * message =E<gt> MESSAGE

The message where this body belongs to.

=item * mime_type =E<gt> STRING|FIELD

The type of data which is added.  You may specify a content of a header
line as STRING, or a FIELD object.  In any case, it will be kept as
a real field (a C<Mail::Message::Field> object).  This relates to the
C<Content-Type> header field.

A mime-type specification consists of two parts: a general class (C<text>,
C<image>, C<application>, etc) and a specific sub-class.  Examples for
specific classes with C<text> are C<plain>, C<html>, and C<xml>.  This
field is case-insensitive but case preserving.  The default mime-type
is C<text/plain>,

=item * transfer_encoding =E<gt> STRING|FIELD

The encoding that the data has.  If the data is to be encoded, than you
will have to call C<encode()> after the body is created.  That will
return a new encoded body.  This field is case-insensitive and relates
to the C<Content-Transfer-Encoding> field in the header.

=back

BE WARNED that, what you specify here are encodings and such which are
already in place.  The options will not trigger conversions.  When you
need conversions, first create a body with options which tell what you've
got, and then call C<encode> for what you need.

Examples:

 my $body = Mail::Message::Body::String->new(file => \*IN,
    mime_type => 'text/html; charset="ISO-8859-1"');

 my $body = Mail::Message::Body::Lines->new(data => ['first', $second],
    charset => 'ISO-10646', transfer_encoding => 'NONE');

 my $body = Mail::Message::Body::Lines->new(data => \@lines,
    transfer_encoding => 'base64');

 my $body = Mail::Message::Body::Lines->new(file => 'picture.gif',
    mime_type => 'image/gif');

=cut

my $body_count = 0;  # to be able to compare bodies for equivalence.

sub new(@)
{   my $class = shift;

    return $class->SUPER::new(@_)
         unless $class eq __PACKAGE__;

    my %args  = @_;
    if(exists $args{file})
    {   require Mail::Message::Body::File;
        return Mail::Message::Body::File->new(@_);
    }

    require Mail::Message::Body::Lines;
    Mail::Message::Body::Lines->new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $filename;

    if(defined(my $file = $args->{file}))
    {
        if(!ref $file)
        {    $self->_data_from_filename($file) or return;
             $filename = $file;
        }
        elsif(ref $file eq 'GLOB')
        {    $self->_data_from_glob($file) or return }
        elsif($file->isa('IO::Handle'))
        {    $self->_data_from_filehandle($file) or return }
        else
        {    croak "Illegal datatype for file option." }
    }
    elsif(defined(my $data = $args->{data}))
    {
        if(!ref $data)
        {   $self->_data_from_lines( [split /(?<=\n)/, $data] ) }
        elsif(ref $data eq 'ARRAY')
        {   $self->_data_from_lines($data) or return }
        else
        {   croak "Illegal datatype for data option." }
    }
    elsif(! $self->isMultipart)
    {   # Neither 'file' nor 'data', so empty body.
        $self->_data_from_lines( [] ) or return;
    }

    # Set the content info

    my ($mime, $transfer, $disp);
    if($args->{disposition}) {$disp = $args->{disposition} }
    elsif(defined $filename)
    {   $disp = Mail::Message::Field->new
          ( 'Content-Disposition' => (-T $filename ? 'inline' : 'attachment'));
        (my $abbrev = $filename) =~ s!.*[/\\]!!;
        $disp->attribute(filename => $abbrev);
    }

    if(defined $args->{mime_type}) {$mime = $args->{mime_type} }
    elsif(defined $filename)
    {   $mime = $mime_types->mimeTypeOf($filename);
        $mime = -T $filename ? 'text/plain' : 'application/octet-stream'
            unless defined $mime;
    }

    $mime = $mime->type if ref $mime && $mime->isa('MIME::Type');

    if(defined(my $based = $args->{based_on}))
    {   $mime     = $based->type        unless defined $mime;
        $transfer = $args->{transfer_encoding} || $based->transferEncoding;
        $disp     = $based->disposition unless defined $disp;

        $self->{MMB_checked} = defined $args->{checked}
           ? $args->{checked} : $based->checked;
    }
    else
    {   $transfer = $args->{transfer_encoding} || 'none';
        $disp     = 'none'              unless defined $disp;
        $self->{MMB_checked} = $args->{checked}|| 0;
    }

    $mime = 'text/plain' unless defined $mime;

    unless(ref $mime)
    {   $mime = Mail::Message::Field->new('Content-Type' => lc $mime);
        $mime->attribute(charset => $args->{charset} || 'us-ascii')
            if $mime->body =~ m!^text/!;
    }

    $transfer = Mail::Message::Field->new('Content-Transfer-Encoding' =>
        lc $transfer) unless ref $transfer;

    $disp     = Mail::Message::Field->new('Content-Disposition' => $disp)
        unless ref $disp;

    @$self{ qw/MMB_type MMB_transfer MMB_disposition/ }
        = ($mime, $transfer, $disp);

    # Set message where the body belongs to.

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMB_seqnr}   = $body_count++;
    $self;
}

#------------------------------------------

=item type

Returns the type of information the body contains.  The is taken from
the header field C<Content-Type>, but may have changed during encoding
--or decoding-- of the body (see the C<encode> method).

The returned is a reference to a C<Mail::Message::Field> object, where
you can ask for the C<body> (main content of the field) and the comment
(after a semicolon).  A field stringifies as its body only.

Example:

 my $msg     = $folder->message(6);
 $msg->get('Content-Type')->print;
    # --> Content-Type: text/plain; charset="us-ascii"

 my $content = $msg->decoded;
 my $type    = $content->type;

 print "This is a $type message";
    # --> This is a text/plain message

 print "Comment: ", $content->comment;
    # --> Comment: charset="us-ascii"

=cut

sub type()             { shift->{MMB_type} }

#------------------------------------------

=item mimeType

Returns a C<MIME::Type> object which is related to this body's type.  This
differs from the C<type> method, which results in a C<Mail::Message::Field>.

=cut

sub mimeType()
{   my $self = shift;
    return $self->{MMB_mime} if exists $self->{MMB_mime};

    my $type = $self->{MMB_type};
    $self->{MMB_mime} = $mime_types->type($type) || MIME::Type->new($type);
}

#------------------------------------------

=item transferEncoding [STRING|FIELD]

Returns the transfer-encoding of the data within this body.  If it
needs to be changed, call the C<encode> or C<decoded> method.

The optional STRING or FIELD enforces a new encoding to be set, without the
actual required translations.

Example:

 my $transfer = $msg->decoded->transferEncoding;
 $transfer->print;
    # --> Content-Encoding: base64

=cut

sub transferEncoding(;$)
{   my $self = shift;
    return $self->{MMB_transfer} unless @_;

    my $set = shift;
    $self->{MMB_transfer} = ref $set ? $set
       : Mail::Message::Field->new('Content-Transfer-Encoding' => $set);
}

#------------------------------------------

=item disposition [STRING|FIELD]

Returns (optionally after setting) how the message can be disposed (unpacked).
The argument can be a STRING (which is converted into a field), or a
fully prepared header field.  The related header field is
C<Content-Disposition>.

=cut

sub disposition(;$)
{   my $self = shift;

    if(@_)
    {   my $disp = shift;
        $self->{MMB_disposition} = ref $disp ? $disp
          : Mail::Message::Field->new('Content-Disposition' => $disp);
    }

    $self->{MMB_disposition};
}

#------------------------------------------

=item checked [BOOLEAN]

Returns whether the body encoding has been checked or not (optionally
after setting the flag to a new value).

=cut

sub checked(;$)
{   my $self = shift;
    @_ ? $self->{MMB_checked} = shift : $self->{MMB_checked};
}

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
        weaken($self->{MMB_message});
    }
    $self->{MMB_message};
}

#------------------------------------------

# All body implementations shall implement all of the following!!

sub _data_from_filename(@_)   {shift->notImplemented}
sub _data_from_filehandle(@_) {shift->notImplemented}
sub _data_from_glob(@_)       {shift->notImplemented}
sub _data_from_lines(@_)      {shift->notImplemented}

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

=item modified [BOOL]

Returns whether the body is flagged as being modified, optionally
after setting it to BOOL.

=cut

sub modified(;$)
{  my $self = shift;
   @_? $self->{MM_modified} = shift : $self->{MM_modified};
}

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

=item decoded OPTIONS

Returns a body --an object which is (a sub-)class of a C<Mail::Message::Body>--
which contains a simplified representation of textual data.  The returned
object may be the object where this is called on, but may also be a new
body of any type.

 my $dec = $body->decoded;
 
is equivalent with

 my $dec = $body->encode(mime_type => 'text/plain', charset => 'us-ascii',
    transfer_encoding => 'NONE');

The C<$dec> which is returned is a body.  Ask with the C<mimeType> method
what is produced.  This body is B<not related to a header>, so you can
not ask C<$dec-E<gt>get('Content-Type')>!

 OPTION      DESCRIBED IN            DEFAULT
 result_type Mail::Message::Body     <same as current>

=cut

sub decoded(@)
{   my $self = shift;
    $self->encode
     ( mime_type         => 'text/plain'
     , charset           => 'us-ascii'
     , transfer_encoding => 'none'
     , @_
     );
}

#------------------------------------------

my @in_encode = qw/check encode encoded isBinary unify/;
my %in_module = map { ($_ => 'encode') } @in_encode;

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;

    my $mod = $in_module{$call} || 'construct';
    if($mod eq 'encode'){ require Mail::Message::Body::Encode    }
    else                { require Mail::Message::Body::Construct }

    no strict 'refs';
    $self->can($call) ? $self->$call(@_) : $self->SUPER::AUTOLOAD->$call(@_);
}   

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item read PARSER, HEAD, BODYTYPE [,CHARS [,LINES]]

Read the body with the PARSER from file. The implementation of this method
will differ between types of bodies.  The BODYTYPE argument is a class name
or a code reference of a routine which can produce a class name, and is
used in multipart bodies to determine the type of the body for each part.

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

=item clone

Return a copy of this body, usually to be included in a cloned
message (see C<Mail::Message::clone>).

=cut

sub clone() {shift->notImplemented}

#------------------------------------------

=item fileLocation

The location of the body in the file.  Returned a list containing begin and
end.  The begin is the offsets of the first byte if the folder used for
this body.  The end is the offset of the first byte of the next message.

=cut

sub fileLocation() {
    my $self = shift;
    @$self{ qw/MMB_begin MMB_end/ };
}

#------------------------------------------

=item moveLocation [DISTANCE]

Move the registration of the message to a new location over DISTANCE.  This
is called when the message is written to a new version of the same
folder-file.

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMB_begin} -= $dist;
    $self->{MMB_end}   -= $dist;
    $self;
}

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

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
