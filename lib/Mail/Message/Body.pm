use strict;
use warnings;

package Mail::Message::Body;
use base 'Mail::Reporter';

use Mail::Message::Field;
use Mail::Message::Body::Lines;
use Mail::Message::Body::File;

use Carp;
use Scalar::Util     qw/weaken refaddr/;
use File::Basename   qw/basename/;

use MIME::Types;
my $mime_types = MIME::Types->new;
my $mime_plain = $mime_types->type('text/plain');

=chapter NAME

Mail::Message::Body - the data of a body in a message

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $body  = $msg->body;
 my @text  = $body->lines;
 my $text  = $body->string;
 my $file  = $body->file;  # IO::File
 $body->print(\*FILE);

 my $content_type = $body->type;
 my $transfer_encoding = $body->transferEncoding;
 my $encoded = $body->encode(mime_type => 'text/html',
    charset => 'us-ascii', transfer_encoding => 'none');\n";
 my $decoded = $body->decoded;

=chapter DESCRIPTION

The encoding and decoding functionality of a M<Mail::Message::Body> is
implemented in the M<Mail::Message::Body::Encode> package.  That package is
automatically loaded when encoding and decoding of messages needs to take
place.  Methods to simply build an process body objects are implemented
in M<Mail::Message::Body::Construct>.

The body of a message (a M<Mail::Message> object) is stored in one of the
many body types.  The functionality of each body type is equivalent, but there
are performance differences.  Each body type has its own documentation
with details about its implementation.
=chapter OVERLOADED

=overload @{}

When a body object is used as being an array reference, the lines of
the body are returned.  This is the same as using M<lines()>.

=example using a body as array

 print $body->lines->[1];  # second line
 print $body->[1];         # same

 my @lines = $body->lines;
 my @lines = @$body;       # same

=overload bool

Always returns a true value, which is needed to have overloaded
objects to be used as in C<if($body)>.  Otherwise, C<if(defined $body)>
would be needed to avoid a runtime error.

=overload ""

(stringification) Returns the body as string --which will trigger
completion-- unless called to produce a string for C<Carp>.  The latter
to avoid deep recursions.

=example stringification of body

 print $msg->body;   # implicit by print

 my $body = $msg->body;
 my $x    = "$body"; # explicit by interpolation

=overload '==' and '!='

(numeric comparison) compares if two references point to the
same message.  This only produces correct results is both arguments
are message references B<within the same folder>.

=example use of numeric comparison on a body

 my $skip = $folder->message(3);
 foreach my $msg (@$folder)
 {   next if $msg == $skip;
     $msg->send;
 }

=cut

use overload
    bool  => sub {1}   # $body->print if $body
  , '""'  => 'string_unless_carp'
  , '@{}' => 'lines'
  , '=='  => sub {ref $_[1] && refaddr $_[0] == refaddr $_[1]}
  , '!='  => sub {ref $_[1] && refaddr $_[0] != refaddr $_[1]};

#------------------------------------------

=chapter METHODS

=section Constructors

=c_method new %options

BE WARNED that, what you specify here are encodings and such which are
already in place.  The options will not trigger conversions.  When you
need conversions, first create a body with options which tell what you've
got, and then call M<encode()> for what you need.

=option  based_on BODY
=default based_on undef
The information about encodings must be taken from the specified BODY,
unless specified differently.

=option  charset CHARSET|'PERL'
=default charset C<'PERL'> or <undef>
Defines the character-set which is used in the data.  Only useful in
combination with a C<mime_type> which refers to C<text> in any shape,
which does not contain an explicit charset already.  This field is
case-insensitive.

When a known CHARSET is provided and the mime type says "text", then the
data is expected to be bytes in that particular encoding (see M<Encode>).
When 'PERL' is given, then then the data is in Perl's internal encoding
(either latin1 or utf8, you shouldn't know!) More details in
L</Character encoding PERL>

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

=option  description STRING|FIELD
=default description undef
Informal information about the body content.  The data relates to the
C<Content-Description> field.  Specify a STRING which will become the
field content, or a real FIELD.

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

=option  content_id STRING
=default content_id undef

In multipart/related MIME content, the content_id is required to
allow access to the related content via a cid:<...> descriptor of
an inline disposition.

A C<Content-ID> is supposed to be globally unique.  As such, it
is common to append '@computer.domain' to the end of some unique
string.  As other content in the multipart/related container also
needs to know what this C<Content-ID> is, this should be left to
the imagination of the person making the content (for now).

As a MIME header field, the C<Content-ID> string is expected to
be inside angle brackets

=option  eol 'CR'|'LF'|'CRLF'|'NATIVE'
=default eol C<'NATIVE'>
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
=default mime_type C<'text/plain'>
The type of data which is added.  You may specify a content of a header
line as STRING, or a FIELD object.  You may also specify a M<MIME::Type>
object.  In any case, it will be kept internally as
a real field (a M<Mail::Message::Field> object).  This relates to the
C<Content-Type> header field.

A mime-type specification consists of two parts: a general class (C<text>,
C<image>, C<application>, etc) and a specific sub-class.  Examples for
specific classes with C<text> are C<plain>, C<html>, and C<xml>.  This
field is case-insensitive but case preserving.  The default mime-type
is C<text/plain>,

=option  transfer_encoding STRING|FIELD
=default transfer_encoding C<'none'>
The encoding that the data has.  If the data is to be encoded, than you
will have to call M<encode()> after the body is created.  That will
return a new encoded body.  This field is case-insensitive and relates
to the C<Content-Transfer-Encoding> field in the header.

=option  modified BOOLEAN
=default modified <false>
Whether the body is flagged modified, directly from its creation.

=examples

 my $body = Mail::Message::Body::String->new(file => \*IN,
    mime_type => 'text/html; charset="ISO-8859-1"');

 my $body = Mail::Message::Body::Lines->new(data => ['first', $second],
    charset => 'ISO-10646', transfer_encoding => 'none');

 my $body = Mail::Message::Body::Lines->new(data => \@lines,
    transfer_encoding => 'base64');

 my $body = Mail::Message::Body::Lines->new(file => 'picture.gif',
    mime_type => 'image/gif', content_id => '<12345@example.com>',
    disposition => 'inline');

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

    $self->{MMB_modified} = $args->{modified} || 0;

    my $filename;
    if(defined(my $file = $args->{file}))
    {
        if(!ref $file)
        {   $self->_data_from_filename($file) or return;
            $filename = $file;
        }
        elsif(ref $file eq 'GLOB')
        {   $self->_data_from_glob($file) or return }
        elsif($file->isa('IO::Handle'))
        {   $self->_data_from_filehandle($file) or return }
        else
        {   croak "message body: illegal datatype `".ref($file)."' for file option" }
    }
    elsif(defined(my $data = $args->{data}))
    {
        if(!ref $data)
        {   my @lines = split /^/, $data;
            $self->_data_from_lines(\@lines)
        }
        elsif(ref $data eq 'ARRAY')
        {   $self->_data_from_lines($data) or return;
        }
        else
        {   croak "message body: illegal datatype `".ref($data)."' for data option" }
    }
    elsif(! $self->isMultipart && ! $self->isNested)
    {   # Neither 'file' nor 'data', so empty body.
        $self->_data_from_lines( [] ) or return;
    }

    # Set the content info

    my ($mime, $transfer, $disp, $charset, $descr, $cid) = @$args{
       qw/mime_type transfer_encoding disposition charset
          description content_id/ }; 

    if(defined $filename)
    {   $disp = Mail::Message::Field->new
           ('Content-Disposition' => (-T $filename ? 'inline':'attachment')
           , filename => basename($filename)
           ) unless defined $disp;

        unless(defined $mime)
        {   $mime = $mime_types->mimeTypeOf($filename);
            $mime = -T $filename ? 'text/plain' : 'application/octet-stream'
                unless defined $mime;
        }
    }

    if(ref $mime && $mime->isa('MIME::Type'))
    {   $mime     = $mime->type;
    }

    if(defined(my $based = $args->{based_on}))
    {   $mime     = $based->type             unless defined $mime;
        $transfer = $based->transferEncoding unless defined $transfer;
        $disp     = $based->disposition      unless defined $disp;
        $descr    = $based->description      unless defined $descr;
        $cid      = $based->contentId        unless defined $cid;

        $self->{MMB_checked}
               = defined $args->{checked} ? $args->{checked} : $based->checked;
    }
    else
    {   $transfer = $args->{transfer_encoding};
        $self->{MMB_checked} = $args->{checked} || 0;
    }

    $mime ||= 'text/plain';
    $mime = $self->type($mime);
    $mime->attribute(charset => ($charset || 'PERL'))
        if $mime =~ m!^text/!i && !$mime->attribute('charset');

    $self->transferEncoding($transfer) if defined $transfer;
    $self->disposition($disp)          if defined $disp;
    $self->description($descr)         if defined $descr;
    $self->contentId($cid)             if defined $cid;
    $self->type($mime);

    $self->{MMB_eol}   = $args->{eol} || 'NATIVE';

    # Set message where the body belongs to.

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMB_seqnr} = $body_count++;
    $self;
}

=method clone
Return a copy of this body, usually to be included in a cloned
message. Use M<Mail::Message::clone()> for a whole message.
=cut

sub clone() {shift->notImplemented}

#------------------------------------------

=section Constructing a body

=method decoded %options

Returns a body, an object which is (a sub-)class of a M<Mail::Message::Body>,
which contains a simplified representation of textual data.  The returned
object may be the object where this is called on, but may also be a new
body of any type.

 my $dec = $body->decoded;
 
is equivalent with

 my $dec = $body->encode
   ( mime_type         => 'text/plain'
   , transfer_encoding => 'none'
   , charset           => 'PERL'
   );

The C<$dec> which is returned is a body.  Ask with the M<mimeType()> method
what is produced.  This C<$dec> body is B<not related to a header>.

=option  result_type CLASS
=default result_type <same as current>

=cut

sub decoded(@)
{   my $self = shift;
    $self->encode(charset => 'PERL', transfer_encoding => 'none', @_);
}

=method eol ['CR'|'LF'|'CRLF'|'NATIVE']
Returns the character (or characters) which are used to separate lines
within this body.  When a kind of separator is specified, the body is
translated to contain the specified line endings.

=example
 my $body = $msg->decoded->eol('NATIVE');
 my $char = $msg->decoded->eol;

=warning Unknown line terminator $eol ignored
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

    return $self if $eol eq $self->{MMB_eol} && $self->checked;
    my $lines = $self->lines;
    if(@$lines)
    {   # sometimes texts lack \n on last line
        $lines->[-1] .= "\n";
       

           if($eol eq 'CR')   {s/[\015\012]+$/\015/     for @$lines}
        elsif($eol eq 'LF')   {s/[\015\012]+$/\012/     for @$lines}
        elsif($eol eq 'CRLF') {s/[\015\012]+$/\015\012/ for @$lines}
        else
        {   $self->log(WARNING => "Unknown line terminator $eol ignored");
            return $self->eol('NATIVE');
        }
    }

    (ref $self)->new(based_on => $self, eol => $eol, data => $lines);
}

#------------------------------------------

=section The body

=method message [$message]
Returns the message (or message part) where this body belongs to,
optionally setting it to a new $message first.  If C<undef> is passed,
the body will be disconnected from the message.

=cut

sub message(;$)
{   my $self = shift;
    if(@_)
    {   if($self->{MMB_message} = shift)
        {   weaken $self->{MMB_message};
        }
    }
    $self->{MMB_message};
}

=method isDelayed
Returns a true or false value, depending on whether the body of this
message has been read from file.  This can only false for a
M<Mail::Message::Body::Delayed>.
=cut

sub isDelayed() {0}

=method isMultipart
Returns whether this message-body contains parts which are messages
by themselves.
=cut

sub isMultipart() {0}

=method isNested
Only true for a message body which contains exactly one sub-message:
the C<Mail::Message::Body::Nested> body type.
=cut

sub isNested() {0}

=method partNumberOf $part
Returns a string for multiparts and nested, otherwise an error.  It is
used in M<Mail::Message::partNumber()>.
=cut

sub partNumberOf($)
{   shift->log(ERROR => 'part number needs multi-part or nested');
    'ERROR';
}

#------------------------------------------

=section About the payload

=method type [STRING|$field]
Returns the type of information the body contains as
M<Mail::Message::Field> object.  The type is taken from the header
field C<Content-Type>. If the header did not contain that field,
then you will get a default field containing C<text/plain>.

You usually can better use M<mimeType()>, because that will return a
clever object with type information.

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

sub type(;$)
{   my $self = shift;
    return $self->{MMB_type} if !@_ && defined $self->{MMB_type};

    delete $self->{MMB_mime};
    my $type = defined $_[0] ? shift : 'text/plain';

    $self->{MMB_type} = ref $type ? $type->clone
      : Mail::Message::Field->new('Content-Type' => $type);
}

=method mimeType
Returns a M<MIME::Type> object which is related to this body's type.  This
differs from the C<type> method, which results in a M<Mail::Message::Field>.

=example
 if($body->mimeType eq 'text/html') {...}
 print $body->mimeType->simplified;
=cut

sub mimeType()
{   my $self  = shift;
    return $self->{MMB_mime} if exists $self->{MMB_mime};

    my $field = $self->{MMB_type};
    my $body  = defined $field ? $field->body : '';

    return $self->{MMB_mime} = $mime_plain
       unless length $body;

    $self->{MMB_mime}
       = $mime_types->type($body) || MIME::Type->new(type => $body);
}

=method charset
Returns the character set which is used in the text body as string.  This
is part of the result of what the C<type> method returns.
=cut

sub charset() { shift->type->attribute('charset') }

=method transferEncoding [STRING|$field]
Returns the transfer-encoding of the data within this body as
M<Mail::Message::Field> (which stringifies to its content).  If it
needs to be changed, call the M<encode()> or M<decoded()> method.
When no encoding is present, the field contains the text C<none>.

The optional STRING or $field enforces a new encoding to be set, without the
actual required translations.

=examples

 my $transfer = $msg->decoded->transferEncoding;
 $transfer->print;   # --> Content-Encoding: base64
 print $transfer;    # --> base64

 if($msg->body->transferEncoding eq 'none') {...}

=cut

sub transferEncoding(;$)
{   my $self = shift;
    return $self->{MMB_transfer} if !@_ && defined $self->{MMB_transfer};

    my $set = defined $_[0] ? shift : 'none';
    $self->{MMB_transfer} = ref $set ? $set->clone
       : Mail::Message::Field->new('Content-Transfer-Encoding' => $set);
}

=method description [STRING|$field]
Returns (optionally after setting) the informal description of the body
content.  The related header field is C<Content-Description>.
A M<Mail::Message::Field> object is returned (which stringifies into
the field content).  The field content will be C<none> if no disposition
was specified.

The argument can be a STRING (which is converted into a field), or a
fully prepared header field.
=cut

sub description(;$)
{   my $self = shift;
    return $self->{MMB_description} if !@_ && $self->{MMB_description};

    my $disp = defined $_[0] ? shift : 'none';
    $self->{MMB_description} = ref $disp ? $disp->clone
       : Mail::Message::Field->new('Content-Description' => $disp);
}

=method disposition [STRING|$field]
Returns (optionally after setting) how the message can be disposed
(unpacked).  The related header field is C<Content-Disposition>.
A M<Mail::Message::Field> object is returned (which stringifies into
the field content).  The field content will be C<none> if no disposition
was specified.

The argument can be a STRING (which is converted into a field), or a
fully prepared header field.
=cut

sub disposition(;$)
{   my $self = shift;
    return $self->{MMB_disposition} if !@_ && $self->{MMB_disposition};

    my $disp = defined $_[0] ? shift : 'none';

    $self->{MMB_disposition} = ref $disp ? $disp->clone
       : Mail::Message::Field->new('Content-Disposition' => $disp);
}

=method contentId [STRING|$field]
Returns (optionally after setting) the id (unique reference) of a
message part.  The related header field is C<Content-ID>.
A M<Mail::Message::Field> object is returned (which stringifies into
the field content).  The field content will be C<none> if no disposition
was specified.

The argument can be a STRING (which is converted into a field), or a
fully prepared header $field.
=cut

sub contentId(;$)
{   my $self = shift;
    return $self->{MMB_id} if !@_ && $self->{MMB_id};

    my $cid = defined $_[0] ? shift : 'none';
    $self->{MMB_id} = ref $cid ? $cid->clone
       : Mail::Message::Field->new('Content-ID' => $cid);
}

=method checked [BOOLEAN]
Returns whether the body encoding has been checked or not (optionally
after setting the flag to a new value).
=cut

sub checked(;$)
{   my $self = shift;
    @_ ? ($self->{MMB_checked} = shift) : $self->{MMB_checked};
}

=method nrLines
Returns the number of lines in the message body.  For multi-part messages,
this includes the header lines and boundaries of all the parts.
=cut

sub nrLines(@)  {shift->notImplemented}

=method size
The total number of bytes in the message body. The size of the body
is computed in the shape it is in. For example, if this is a base64
encoded message, the size of the encoded data is returned; you may
want to call M<Mail::Message::decoded()> first.
=cut

sub size(@)  {shift->notImplemented}

#------------------------------------------

=section Access to the payload

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

=method lines
Return the content of the body as a list of lines (in LIST context) or a
reference to an array of lines (in SCALAR context).  In scalar context the
array of lines is cached to avoid needless copying and therefore provide
much faster access for large messages.

To just get the number of lines in the body, use the M<nrLines()> method,
which is usually much more efficient.

BE WARNED: For some types of bodies the reference will refer to the
original data. You must not change the referenced data! If you do, some of
the essential internal variables of the M<Mail::Message::Body> may not be
updated.

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

=method file
Return the content of the body as a file handle.  The returned stream may
be a real file, or a simulated file in any form that Perl supports.  While
you may not be able to write to the file handle, you can read from it.

WARNING: Even if the file handle supports writing, do not write
to the file handle. If you do, some of the internal values of the
M<Mail::Message::Body> may not be updated.
=cut

sub file(;$) {shift->notImplemented}

=method print [$fh]
Print the body to the specified $fh (defaults to the selected handle).
The handle may be a GLOB, an M<IO::File> object, or... any object with a
C<print()> method will do.  Nothing useful is returned.
=cut

sub print(;$) {shift->notImplemented}

=method printEscapedFrom $fh
Print the body to the specified $fh but all lines which start
with 'From ' (optionally already preceded by E<gt>'s) will habe an E<gt>
added in front.  Nothing useful is returned.
=cut

sub printEscapedFrom($) {shift->notImplemented}

=method write %options
Write the content of the body to a file.  Be warned that you may want to
decode the body before writing it!

=requires filename FILENAME

=example write the data to a file
 use File::Temp;
 my $fn = tempfile;
 $message->decoded->write(filename => $fn)
    or die "Couldn't write to $fn: $!\n";

=example using the content-disposition information to write
 use File::Temp;
 my $dir = tempdir; mkdir $dir or die;
 my $fn  = $message->body->dispositionFilename($dir);
 $message->decoded->write(filename => $fn)
    or die "Couldn't write to $fn: $!\n";

=cut

sub write(@)
{   my ($self, %args) = @_;
    my $filename = $args{filename};
    die "No filename for write() body" unless defined $filename;

    open OUT, '>', $filename or return;
    $self->print(\*OUT);
    close OUT or return undef;
    $self;
}

=method endsOnNewline
Returns whether the last line of the body is terminated by a new-line
(in transport it will become a CRLF).  An empty body will return true
as well: the newline comes from the line before it.
=cut

sub endsOnNewline() {shift->notImplemented}

=method stripTrailingNewline
Remove the newline from the last line, or the last line if it does not
contain anything else than a newline.
=cut

sub stripTrailingNewline() {shift->notImplemented}

#------------------------------------------

=section Internals

=method read $parser, $head, $bodytype, [$chars, [$lines]]

Read the body with the $parser from file. The implementation of this method
will differ between types of bodies.  The $bodytype argument is a class name
or a code reference of a routine which can produce a class name, and is
used in multipart bodies to determine the type of the body for each part.

The $chars argument is the estimated number of bytes in the body, or
C<undef> when this is not known.  This data can sometimes be derived from
the header (the C<Content-Length> line) or file-size.

The second argument is the estimated number of $lines of the body.  It is less
useful than the $chars but may be of help determining whether the message
separator is trustworthy.  This value may be found in the C<Lines> field
of the header.

=cut

sub read(@) {shift->notImplemented}

=method contentInfoTo $head
Copy the content information (the C<Content-*> fields) into the specified
$head.  The body was created from raw data without the required information,
which must be added.  See also M<contentInfoFrom()>.
=cut

sub contentInfoTo($)
{   my ($self, $head) = @_;
    return unless defined $head;

    my $lines  = $self->nrLines;
    my $size   = $self->size;
    $size     += $lines if $Mail::Message::crlf_platform;

    $head->set($self->type);
    $head->set($self->transferEncoding);
    $head->set($self->disposition);
    $head->set($self->description);
    $head->set($self->contentId);
    $self;
}

=method contentInfoFrom $head
Transfer the body related info from the header into this body.
=cut

sub contentInfoFrom($)
{   my ($self, $head) = @_;

    $self->type($head->get('Content-Type', 0));
    $self->transferEncoding($head->get('Content-Transfer-Encoding'));
    $self->disposition($head->get('Content-Disposition'));
    $self->description($head->get('Content-Description'));
    $self->contentId($head->get('Content-ID'));

    delete $self->{MMB_mime};
    $self;

}

=method modified [BOOLEAN]
Change the body modification flag.  This will force a re-write of the body
to a folder file when it is closed.  It is quite dangerous to change the
body: the same body may be shared between messages within your program.

Especially be warned that you have to change the message-id when you
change the body of the message: no two messages should have the same id.

Without value, the current setting is returned, although you can better use
M<isModified()>.
=cut

sub modified(;$)
{  my $self = shift;
   return $self->isModified unless @_;  # compat 2.036
   $self->{MMB_modified} = shift;
}

=method isModified
Returns whether the body has changed.
=cut

sub isModified() { shift->{MMB_modified} }

=method fileLocation [$begin, $end]
The location of the body in the file.  Returned a list containing begin and
end.  The begin is the offsets of the first byte if the folder used for
this body.  The end is the offset of the first byte of the next message.
=cut

sub fileLocation(;@)
{   my $self = shift;
    return @$self{ qw/MMB_begin MMB_end/ } unless @_;
    @$self{ qw/MMB_begin MMB_end/ } = @_;
}

=method moveLocation [$distance]
Move the registration of the message to a new location over $distance.  This
is called when the message is written to a new version of the same
folder-file.
=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMB_begin} -= $dist;
    $self->{MMB_end}   -= $dist;
    $self;
}

=method load
Be sure that the body is loaded.  This returns the loaded body.
=cut

sub load() {shift}

#------------------------------------------

=section Error handling

=method AUTOLOAD
When an unknown method is called on a message body object, this may
not be problematic.  For performance reasons, some methods are
implemented in separate files, and only demand-loaded.  If this
delayed compilation of additional modules does not help, an error
will be produced.
=cut

my @in_encode = qw/check encode encoded eol isBinary isText unify
                   dispositionFilename/;
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

=chapter DETAILS

=section Access to the body

A body can be contained in a message, but may also live without a message.
In both cases it stores data, and the same questions can be asked: what
type of data it is, how many bytes and lines, what encoding is used.  Any
body can be encoded and decoded, returning a new body object.  However, 
bodies which are part of a message will always be in a shape that they can
be written to a file or send to somewhere: they will be encoded if needed.

=example

 my $body    = M<Mail::Message::Body::String>->new(mime_type => 'image/gif');
 $body->print(\*OUT);    # this is binary image data...

 my $encoded = $message->body($body);
 $encoded->print(\*OUT); # ascii data, encoded image

Now encoded refers to the body of the C<$message> which is the content of
C<$body> in a shape that it can be transmitted.  Usually C<base64> encoding
is used.
  
=section Body class implementation

The body of a message can be stored in many ways.  Roughly, the
implementations can be split in two groups: the data collectors and
the complex bodies. The primer implement various ways to access data,
and are full compatible: they only differ in performance and memory
footprint under different circumstances.  The latter are created to
handle complex multiparts and lazy extraction.

=subsection Data collector bodies

=over 4

=item * M<Mail::Message::Body::String>
The whole message body is stored in one scalar.  Small messages can be
contained this way without performance penalties.

=item * M<Mail::Message::Body::Lines>
Each line of the message body is stored as single scalar.  This is a
useful representation for a detailed look in the message body, which is
usually line-organized.

=item * M<Mail::Message::Body::File>
The message body is stored in an external temporary file.  This type of
storage is especially useful when the body is large, the total folder is
large, or memory is limited.

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

=subsection Complex bodies

=over 4

=item * M<Mail::Message::Body::Delayed>
The message-body is not yet read, but the exact location of the
body is known so the message can be read when needed.  This is part of
the lazy extraction mechanism.  Once extracted, the object can become
any simple or complex body.

=item * M<Mail::Message::Body::Multipart>
The message body contains a set of sub-messages (which can contain
multipart bodies themselves).  Each sub-message is an instance
of M<Mail::Message::Part>, which is an extension of M<Mail::Message>.

=item * M<Mail::Message::Body::Nested>
Nested messages, like C<message/rfc822>: they contain a message in
the body.  For most code, they simply behave like multiparts.

=back

=section Character encoding PERL

A body object can be part of a message, or stand-alone.  In case it
is a part of a message, the "transport encoding" and the content must
be in a shape that the data can be transported via SMTP.

However, when you want to process the body data in simple Perl (or when
you construct the body data from normal Perl strings), you need to be
aware of Perl's internal representation of strings. That can either be
latin1 or utf8 (not real UTF-8, but something alike, see the perlunicode
manual page)  So, before you start using the data from an incoming message,
do

    my $body  = $msg->decoded;
    my @lines = $body->lines;

Now, the body has character-set 'PERL' (when it is text)

When you create a new body which contains text content (the default),
it will be created with character-set 'PERL' unless you specify a
character-set explicitly.

   my $body = Mail::Box::Body::Lines->new(data => \@lines);
   # now mime=text/plain, charset=PERL

   my $msg  = Mail::Message->buildFromBody($body);
   $msg->body($body);
   $msg->attach($body);   # etc
   # these all will convert the charset=PERL into real utf-8

=cut

1;
