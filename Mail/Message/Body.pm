use strict;
use warnings;

package Mail::Message::Body;
use base 'Mail::Reporter';

use Mail::Message::Field;
use Mail::Message::Body::Lines;
use Mail::Message::Body::File;

use Carp;
use Scalar::Util 'weaken';

use overload bool  => sub {1}   # $body->print if $body
           , '""'  => 'string_unless_carp'
           , '@{}' => 'lines'
           , '=='  => sub {$_[0]->{MMB_seqnr}==$_[1]->{MMB_seqnr}}
           , '!='  => sub {$_[0]->{MMB_seqnr}!=$_[1]->{MMB_seqnr}};

use MIME::Types;
my $mime_types = MIME::Types->new;

=head1 NAME

Mail::Message::Body - the data of a body in a message

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $body  = $msg->body;
 my @text  = $body->lines;
 my $text  = $body->string;
 my IO::Handle $file = $body->file;
 $body->print(\*FILE);

 my $content_type = $body->type;
 my $transfer_encoding = $body->transferEncoding;
 my $encoded  = $body->encode(mime_type => 'text/html',
    charset => 'us-ascii', transfer_encoding => 'NONE');
 my $decoded  = $body->decoded;

=head1 DESCRIPTION

The encoding and decoding functionality of a Mail::Message::Body is
implemented in the Mail::Message::Body::Encode package.  That package is
automatically loaded when encoding and decoding of messages needs to take
place.

The body of a message (a Mail::Message object) is stored in one of the
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

=item * Mail::Message::Body::Lines

Each line of the message body is stored as single scalar.  This is a
useful representation for a detailed look in the message body, which is
usually line-organized.

=item * Mail::Message::Body::String

The whole message body is stored in one scalar.  Small messages can be
contained this way without performance penalties.

=item * Mail::Message::Body::File

The message body is stored in an external temporary file.  This type of
storage is especially useful when the body is large, the total folder is
large, or memory is limited.

=item * Mail::Message::Body::Delayed

The message-body is not yet read, but the exact location of the
body is known so the message can be read when needed.

=item * Mail::Message::Body::Multipart

The message body contains a set of sub-messages (which can contain
multipart bodies themselves).  Each sub-message is an instance
of Mail::Message::Part, which is an extension of Mail::Message.

=item * Mail::Message::Body::Nested

Nested messages, like C<message/rfc822>: they contain a message in
the body.  For most code, they simply behave like multiparts.

=item * Mail::Message::Body::InFolder

NOT IMPLEMENTED YET.
The message is kept in the folder, and is only taken out when the
content is changed.

=item * Mail::Message::Body::External

NOT IMPLEMENTED YET.
The message is kept in a separate file, usually because the message body
is large.  The difference with the C<::External> object is that this external
storage stays this way between closing and opening of a folder. The
C<::External> object only uses a file when the folder is open.

=back

Each body type has methods to produce the storage of the other types.
As example, you can ask any body type for the message as a list of lines,
but this call will be most efficient for the MM::Body::Lines type.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

BE WARNED that, what you specify here are encodings and such which are
already in place.  The options will not trigger conversions.  When you
need conversions, first create a body with options which tell what you've
got, and then call encode() for what you need.

=option  based_on BODY
=default based_on undef

The information about encodings must be taken from the specified BODY,
unless specified differently.

=option  charset STRING
=default charset 'us-ascii'

Defines the character-set which is used in the data.  Only useful in
combination with a C<mime_type> which refers to C<text> in any shape.
This field is case-insensitive.

=option  checked BOOLEAN
=default checked <false>

Whether the added information has been check not to contain illegal
octets with respect to the transfer encoding and mime type.  If not
checked, and then set as body for a message, it will be.

=option  data ARRAY-OF-LINES | STRING
=default data undef

The content of the body.  The only way to set the content of a body
is during the creation of the body.  So if you want to modify the content
of a message, you need to create a new body with the new content and
add that to the body.  The reason behind this, is that correct encodings
and body information must be guaranteed.  It avoids your hassle in
calculating the number of lines in the body, and checking whether bad
characters are enclosed in text.

Specify a reference to an ARRAY of lines, each terminated by a newline.
Or one STRING which may contain multiple lines, separated and terminated
by a newline.

=option  disposition STRING|FIELD
=default disposition undef

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
reader of the message when it is extracted.

=option  eol 'CR'|'LF'|'CRLF'|'NATIVE'
=default eol 'NATIVE'

Convert the message into having the specified string as line terminator
for all lines in the body.  C<NATIVE> is used to represent the C<\n>
on the current platform and will be translated in the applicable one.

BE WARNED that folders with a non-native encoding may appear on your
platform, for instance in Windows folders handled from a UNIX system.
The eol encoding has effect on the size of the body!

=option  file FILENAME|FILEHANDLE|IOHANDLE
=default file undef

Read the data from the specified file, file handle, or object of
type C<IO::Handle>.

=option  message MESSAGE
=default message undef

The message where this body belongs to.

=option  mime_type STRING|FIELD|MIME
=default mime_type 'text/plain'

The type of data which is added.  You may specify a content of a header
line as STRING, or a FIELD object.  You may also specify a C<MIME::Type>
object.  In any case, it will be kept internally as
a real field (a Mail::Message::Field object).  This relates to the
C<Content-Type> header field.

A mime-type specification consists of two parts: a general class (C<text>,
C<image>, C<application>, etc) and a specific sub-class.  Examples for
specific classes with C<text> are C<plain>, C<html>, and C<xml>.  This
field is case-insensitive but case preserving.  The default mime-type
is C<text/plain>,

=option  transfer_encoding STRING|FIELD
=default transfer_encoding 'NONE'

The encoding that the data has.  If the data is to be encoded, than you
will have to call encode() after the body is created.  That will
return a new encoded body.  This field is case-insensitive and relates
to the C<Content-Transfer-Encoding> field in the header.

=option  modified BOOLEAN
=default modified <false>

Whether the body is flagged modified, directly from its creation.

=examples

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

      exists $args{file}
    ? Mail::Message::Body::File->new(@_)
    : Mail::Message::Body::Lines->new(@_);
}

# All body implementations shall implement all of the following!!

sub _data_from_filename(@)   {shift->notImplemented}
sub _data_from_filehandle(@) {shift->notImplemented}
sub _data_from_glob(@)       {shift->notImplemented}
sub _data_from_lines(@)      {shift->notImplemented}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MM_modified} = $args->{modified} || 0;

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
        {   $self->_data_from_lines( [split /^/, $data] ) }
        elsif(ref $data eq 'ARRAY')
        {   $self->_data_from_lines($data) or return }
        else
        {   croak "Illegal datatype for data option." }
    }
    elsif(! $self->isMultipart && ! $self->isNested)
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
            if $mime =~ m!^text/!;
    }

    $transfer = Mail::Message::Field->new('Content-Transfer-Encoding' =>
        lc $transfer) unless ref $transfer;

    $disp     = Mail::Message::Field->new('Content-Disposition' => $disp)
        unless ref $disp;

    @$self{ qw/MMB_type MMB_transfer MMB_disposition/ }
        = ($mime, $transfer, $disp);
    $self->{MMB_eol}   = $args->{eol} || 'NATIVE';

    # Set message where the body belongs to.

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMB_seqnr} = $body_count++;
    $self;
}

#------------------------------------------

=head2 The Body

=cut

#------------------------------------------

=method clone

Return a copy of this body, usually to be included in a cloned
message (see Mail::Message::clone()).

=cut

sub clone() {shift->notImplemented}

#------------------------------------------

=method message [MESSAGE]

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

=method modified [BOOL]

Returns whether the body is flagged as being modified, optionally
after setting it to BOOL.

=cut

sub modified(;$)
{  my $self = shift;
   @_? $self->{MM_modified} = shift : $self->{MM_modified};
}

#------------------------------------------

=method print [FILE]

Print the body to the specified file (defaults to the selected handle)

=cut

sub print(;$) {shift->notImplemented}

#------------------------------------------

=method isDelayed

Returns a true or false value, depending on whether the body of this
message has been read from file.  This can only false for a
Mail::Message::Body::Delayed.

=cut

sub isDelayed() {0}

#------------------------------------------

=method isMultipart

Returns whether this message-body contains parts which are messages
by themselves.

=cut

sub isMultipart() {0}

#------------------------------------------

=method isNested

Only true for a message body which contains exactly one sub-message:
the C<::Nested> body type.

=cut

sub isNested() {0}

#------------------------------------------

=method decoded OPTIONS

Returns a body (an object which is (a sub-)class of a Mail::Message::Body)
which contains a simplified representation of textual data.  The returned
object may be the object where this is called on, but may also be a new
body of any type.

 my $dec = $body->decoded;
 
is equivalent with

 my $dec = $body->encode(mime_type => 'text/plain', charset => 'us-ascii',
    transfer_encoding => 'NONE');

The C<$dec> which is returned is a body.  Ask with the mimeType() method
what is produced.  This body is B<not related to a header>, so you can
not ask C<< $dec->get('Content-Type') >>!

=option  result_type CLASS
=default result_type <same as current>

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

=head2 About the Payload

=cut

#------------------------------------------

=method type

Returns the type of information the body contains.  The type is taken from
the header field C<Content-Type>, but may have changed during encoding
--or decoding-- of the body (see the C<encode> method).

The returned is a reference to a Mail::Message::Field object, where
you can ask for the C<body> (main content of the field) and the comment
(after a semicolon).  To get to the body, you can better use mimeType().

=examples

 my $msg     = $folder->message(6);
 $msg->get('Content-Type')->print;
    # --> Content-Type: text/plain; charset="us-ascii"

 my $content = $msg->decoded;
 my $type    = $content->type;

 print "This is a $type message\n";
    # --> This is a text/plain; charset="us-ascii" message

 print "This is a ", $type->body, "message\n";
    # --> This is a text/plain message

 print "Comment: ", $type->comment, "\n";
    # --> Comment: charset="us-ascii"

=cut

sub type() { shift->{MMB_type} }

#------------------------------------------

=method mimeType

Returns a MIME::Type object which is related to this body's type.  This
differs from the C<type> method, which results in a Mail::Message::Field.

=example

 if($body->mimeType eq 'text/html') {...}
 print $body->mimeType->simplified;

=cut

sub mimeType()
{   my $self = shift;
    return $self->{MMB_mime} if exists $self->{MMB_mime};

    my $type = $self->{MMB_type}->body;

    $self->{MMB_mime}
       = $mime_types->type($type) || MIME::Type->new(type => $type);
}

#------------------------------------------

=method charset

Returns the character set which is used in the text body as string.  This
is part of the result of what the C<type> method returns.

=cut

sub charset() { shift->type->attribute('charset') }

#------------------------------------------

=method transferEncoding [STRING|FIELD]

Returns the transfer-encoding of the data within this body.  If it
needs to be changed, call the encode() or decoded() method.

The optional STRING or FIELD enforces a new encoding to be set, without the
actual required translations.

=examples

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

=method disposition [STRING|FIELD]

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

=method checked [BOOLEAN]

Returns whether the body encoding has been checked or not (optionally
after setting the flag to a new value).

=cut

sub checked(;$)
{   my $self = shift;
    @_ ? $self->{MMB_checked} = shift : $self->{MMB_checked};
}

#------------------------------------------

=method eol ['CR'|'LF'|'CRLF'|'NATIVE']

Returns the character (or characters) which are used to separate lines
within this body.  When a kind of separator is specified, the body
is translated to contain the specified line endings.

=cut

sub eol(;$)
{   my $self = shift;
    return $self->{MMB_eol} unless @_;

    my $eol  = shift;
    if($eol eq 'NATIVE')
    {   $eol = $^O =~ m/^win/i ? 'CRLF'
             : $^O =~ m/^mac/i ? 'CR'
             :                   'LF';
    }

    return $eol if $eol eq $self->{MMB_eol} && $self->checked;
    my $lines = $self->lines;

       if($eol eq 'CR')    {s/[\015\012]+$/\015/     foreach @$lines}
    elsif($eol eq 'LF')    {s/[\015\012]+$/\012/     foreach @$lines}
    elsif($eol eq 'CRLF')  {s/[\015\012]+$/\015\012/ foreach @$lines}
    else
    {   carp "Unknown line terminator $eol ignored.";
        return $self->eol('NATIVE');
    }

    (ref $self)->new
      ( based_on => $self
      , eol      => $eol
      , data     => $lines
      );
}

#------------------------------------------

=method nrLines

Returns the number of lines in the message body.  For multi-part messages,
this includes the header lines and boundaries of all the parts.

=cut

sub nrLines(@)  {shift->notImplemented}

#------------------------------------------

=method size

The total number of bytes in the message body. The size of the body
is computed in the shape it is in. For example, if this is a base64
encoded message, the size of the encoded data is returned; you may
want to call Mail::Message::decode() first.

=cut

sub size(@)  {shift->notImplemented}

#------------------------------------------

=head2 Access to the Payload

=cut

#------------------------------------------

=method string

Return the content of the body as a scalar (a single string).  This is
a copy of the internally kept information.

=examples

 my $text = $body->string;
 print "Body: $body\n";     # by overloading

=cut

sub string() {shift->notImplemented}

sub string_unless_carp()
{   my $self  = shift;
    return $self->string unless (caller)[0] eq 'Carp';

    (my $class = ref $self) =~ s/^Mail::Message/MM/;
    "$class object";
}

#------------------------------------------

=method lines

Return the content of the body as a list of lines (in LIST context) or a
reference to an array of lines (in SCALAR context).  In scalar context the
array of lines is cached to avoid needless copying and therefore provide
much faster access for large messages.

To just get the number of lines in the body, use the nrLines() method,
which is usually much more efficient.

BE WARNED: For some types of bodies the reference will refer to the
original data. You must not change the referenced data! If you do some of
the internal values maintained by the C<Mail::Message::Body> may not be
updated.   Use the data() method instead.

=examples

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

=method file

Return the content of the body as a file handle.  The returned stream may
be a real file, or a simulated file in any form that Perl supports.  While
you may not be able to write to the file handle, you can read from it.

WARNING: Even if the file handle supports writing, do not write to the
file handle. If you do some of the internal values maintained by the
Mail::Message::Body may not be updated.  Use only the data() method
instead.

=cut

sub file(;$) {shift->notImplemented}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method AUTOLOAD

=cut

my @in_encode = qw/check encode encoded eol isBinary isText unify/;
my %in_module = map { ($_ => 'encode') } @in_encode;

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    (my $call = $AUTOLOAD) =~ s/.*\:\://g;

    my $mod = $in_module{$call} || 'construct';
    if($mod eq 'encode'){ require Mail::Message::Body::Encode    }
    else                { require Mail::Message::Body::Construct }

    no strict 'refs';
    return $self->$call(@_) if $self->can($call);  # now loaded

    # Try parental AUTOLOAD
    Mail::Reporter->$call(@_);
}   

#------------------------------------------

=method read PARSER, HEAD, BODYTYPE [,CHARS [,LINES]]

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

=method fileLocation [BEGIN,END]

The location of the body in the file.  Returned a list containing begin and
end.  The begin is the offsets of the first byte if the folder used for
this body.  The end is the offset of the first byte of the next message.

=cut

sub fileLocation(;@) {
    my $self = shift;
    return @$self{ qw/MMB_begin MMB_end/ } unless @_;
    @$self{ qw/MMB_begin MMB_end/ } = @_;
}

#------------------------------------------

=method moveLocation [DISTANCE]

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

=method load

Be sure that the body is loaded.  This returns the loaded body.

=cut

sub load() {shift}

#------------------------------------------

1;
