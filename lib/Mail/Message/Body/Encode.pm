
use strict;
use warnings;

package Mail::Message::Body;
use base 'Mail::Reporter';

use Carp;
use MIME::Types    ();
use File::Basename 'basename';
use Encode         'find_encoding';

use Mail::Message::Field        ();
use Mail::Message::Field::Full  ();

# http://www.iana.org/assignments/character-sets
use Encode::Alias;
define_alias(qr/^unicode-?1-?1-?utf-?([78])$/i => '"UTF-$1"');  # rfc1642

my $mime_types;

=chapter NAME

Mail::Message::Body::Encode - organize general message encodings

=chapter SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(mime_type => 'image/gif',
     transfer_encoding => 'base64');

 my $body = $msg->body;
 my $decoded = $body->decoded;
 my $encoded = $body->encode(transfer_encoding => '7bit');

=chapter DESCRIPTION

Manages the message's body encodings and decodings on request of the
main program.  This package adds functionality to the M<Mail::Message::Body>
class when the M<decoded()> or M<encode()> method is called.

Four types of encodings are handled (in the right order)

=over 4

=item * eol encoding

Various operating systems have different ideas about how to encode the
line termination.  UNIX uses a LF character, MacOS uses a CR, and
Windows uses a CR/LF combination.  Messages which are transported over
Internet will always use the CRLF separator.

=item * transfer encoding

Messages transmitted over Internet have to be plain ASCII.  Complicated
characters and binary files (like images and archives) must be encoded
during transmission to an ASCII representation.

The implementation of the required encoders and decoders is found in
the M<Mail::Message::TransferEnc> set of packages.  The related
manual page lists the transfer encodings which are supported.

=item * mime-type translation

NOT IMPLEMENTED YET

=item * charset conversion


=back

=chapter METHODS


=section Constructing a body

=method encode %options
Encode (translate) a M<Mail::Message::Body> into a different format.
See the DESCRIPTION above.  Options which are not specified will not trigger
conversions.

=option  charset CODESET|'PERL'
=default charset C<PERL> if text
If the CODESET is explicitly specified (for instance C<iso-8859-10>, then
the data is interpreted as raw bytes (blob), not as text.  However, in
case of C<PERL>, it is considered to be an internal representation of
characters (either latin1 or Perl's utf8 --not the same as utf-8--, you should
not know).

=option  mime_type STRING|FIELD
=default mime_type undef
Convert into the specified mime type, which can be specified as STRING
or FIELD.  The FIELD is a M<Mail::Message::Field>, and the STRING is
converted in such object before use.

=option  result_type CLASS
=default result_type <same as source>
The type of body to be created when the body is changed to fulfill the request
on re-coding.  Also the intermediate stages in the translation process (if
needed) will use this type. CLASS must extend M<Mail::Message::Body>.

=option  transfer_encoding STRING|FIELD
=default transfer_encoding undef

=warning No decoder defined for transfer encoding $name.
The data (message body) is encoded in a way which is not currently understood,
therefore no decoding (or recoding) can take place.

=warning No encoder defined for transfer encoding $name.
The data (message body) has been decoded, but the required encoding is
unknown.  The decoded data is returned.

=warning Charset $name is not known
The encoding or decoding of a message body encounters a character set which
is not understood by Perl's M<Encode> module.

=cut

sub encode(@)
{   my ($self, %args) = @_;

    # simplify the arguments
    my $type_from = $self->type;
    my $type_to   = $args{mime_type} || $type_from->clone->study;
    $type_to = Mail::Message::Field::Full->new('Content-Type' => $type_to)
        unless ref $type_to;

    my $transfer = $args{transfer_encoding} || $self->transferEncoding->clone;
    $transfer    = Mail::Message::Field->new('Content-Transfer-Encoding'
        => $transfer) unless ref $transfer;

    my $trans_was = lc $self->transferEncoding;
    my $trans_to  = lc $transfer;

    my ($char_was, $char_to, $from, $to);
    if($type_from =~ m!^text/!i)
    {   $char_was = $type_from->attribute('charset') || 'us-ascii';
        $char_to  = $type_to->attribute('charset');

        if(my $charset = delete $args{charset})
        {   if(!$char_to || $char_to ne $charset)
            {   $char_to = $charset;
                $type_to->attribute(charset => $char_to);
            }
        }
        elsif(!$char_to)
        {   $char_to = 'utf8';
            $type_to->attribute(charset => $char_to);
        }

        if($char_was ne 'PERL')
        {   $from = find_encoding $char_was
                or $self->log(WARNING => "Charset `$char_was' is not known.");
        }
        if($char_to ne 'PERL')
        {   $to = find_encoding $char_to
                or $self->log(WARNING => "Charset `$char_to' is not known.");
        }

        if($trans_to ne 'none' && $char_to eq 'PERL')
        {   # We cannot leave the body into the 'PERL' charset when transfer-
            # encoding is applied.
            $self->log(WARNING => "Transfer-Encoding `$trans_to' requires "
              . "explicit charset, defaulted to utf8");
            $char_to = 'utf8';
        }
    }


    # Any changes to be made?
    if($trans_was eq $trans_to)
    {   return $self if !$from && !$to;
        if($from && $to && $from->name eq $to->name)
        {   # modify charset into an alias, if requested
            $self->charset($char_to) if $char_was ne $char_to;
            return $self;
        }
    }

    my $bodytype  = $args{result_type} || ref $self;

    my $decoded;
    if($trans_was eq 'none')
    {   $decoded = $self }
    elsif(my $decoder = $self->getTransferEncHandler($trans_was))
    {   $decoded = $decoder->decode($self, result_type => $bodytype) }
    else
    {   $self->log(WARNING =>
           "No decoder defined for transfer encoding $trans_was.");
        return $self;
    }

    my $new_data
      = $to   && $char_was eq 'PERL' ? $to->encode($decoded->string)
      : $from && $char_to  eq 'PERL' ? $from->decode($decoded->string)
      : $to && $from && $from->name ne $to->name
      ?    $to->encode($from->decode($decoded->string))
      : undef;

    my $recoded = $new_data ? $bodytype->new(based_on => $decoded
      , data => $new_data, mime_type => $type_to, checked => 1) : $decoded;

    my $trans;
    if($trans_to ne 'none')
    {   $trans = $self->getTransferEncHandler($trans_to)
           or $self->log(WARNING =>
               "No encoder defined for transfer encoding `$trans_to'.");
    }

    my $encoded = defined $trans
      ? $trans->encode($recoded, result_type => $bodytype)
      : $recoded;

    $encoded;
}

#------------------------------------------

=method check

Check the content of the body not to include illegal characters.  Which
characters are considered illegal depends on the encoding of this body.

A body is returned which is checked.  This may be the body where this
method is called upon, but also a new object, when serious changes had
to be made.  If the check could not be made, because the decoder is not
defined, then C<undef> is returned.

=cut

sub check()
{   my $self     = shift;
    return $self if $self->checked;
    my $eol      = $self->eol;

    my $encoding = $self->transferEncoding->body;
    return $self->eol($eol)
       if $encoding eq 'none';

    my $encoder  = $self->getTransferEncHandler($encoding);

    my $checked
      = $encoder
      ? $encoder->check($self)->eol($eol)
      : $self->eol($eol);

    $checked->checked(1);
    $checked;
}

#------------------------------------------

=method encoded

Encode the body to a format what is acceptable to transmit or write to
a folder file.  This returns the body where this method was called
upon when everything was already prepared, or a new encoded body
otherwise.  In either case, the body is checked.

=cut

sub encoded()
{   my $self = shift;

    $mime_types ||= MIME::Types->new;
    my $mime    = $mime_types->type($self->type->body);

    my $charset = $self->charset || '';
    my $enc_was = $self->transferEncoding;
    my $enc     = $enc_was;
    $enc        = defined $mime ? $mime->encoding : 'base64'
        if $enc eq 'none';

    # we could (expensively) try to autodetect character-set used,
    # but everything is a subset of utf-8.
    my $new_charset
       = (!$mime || $mime !~ m!^text/!i)   ? ''
       : (!$charset || $charset eq 'PERL') ? 'utf-8'
       :                                     $charset;

      ($enc_was ne 'none' && $charset eq $new_charset)
    ? $self->check
    : $self->encode(transfer_encoding => $enc, charset => $new_charset);
}

#------------------------------------------

=method unify $body

Unify the type of the given $body objects with the type of the called
body.  C<undef> is returned when unification is impossible.  If the
bodies have the same settings, the $body object is returned unchanged.

Examples:

 my $bodytype = Mail::Message::Body::Lines;
 my $html  = $bodytype->new(mime_type=>'text/html', data => []);
 my $plain = $bodytype->new(mime_type=>'text/plain', ...);

 my $unified = $html->unify($plain);
 # $unified is the data of plain translated to html (if possible).

=cut

sub unify($)
{   my ($self, $body) = @_;
    return $self if $self==$body;

    my $mime     = $self->type;
    my $transfer = $self->transferEncoding;

    my $encoded  = $body->encode
     ( mime_type         => $mime
     , transfer_encoding => $transfer
     );

    # Encode makes the best of it, but is it good enough?

    my $newmime     = $encoded->type;
    return unless $newmime  eq $mime;
    return unless $transfer eq $encoded->transferEncoding;
    $encoded;
}

#------------------------------------------

=section About the payload

=method isBinary

Returns true when the un-encoded message is binary data.  This information
is retrieved from knowledge provided by M<MIME::Types>.

=cut

sub isBinary()
{   my $self = shift;
    $mime_types ||= MIME::Types->new(only_complete => 1);
    my $type = $self->type                    or return 1;
    my $mime = $mime_types->type($type->body) or return 1;
    $mime->isBinary;
}
 
=method isText
Returns true when the un-encoded message contains printable
text.
=cut

sub isText() { not shift->isBinary }

=method dispositionFilename [$directory]
Returns the name which can be used as filename to store the information
in the indicated $directory. To get a filename, various fields are searched
for C<filename> and C<name> attributes.  Without $directory, the name found
will be returned.

Only the basename of the found name will be used, for security reasons:
otherwise, it may be possible to access other directories than the
one indicated.  If no name was found, or the name is already in use,
then an unique name is generated.

=cut

sub dispositionFilename(;$)
{   my $self = shift;
    my $raw;

    my $field;
    if($field = $self->disposition)
    {   $field = $field->study if $field->can('study');
        $raw   = $field->attribute('filename')
              || $field->attribute('file')
              || $field->attribute('name');
    }

    if(!defined $raw && ($field = $self->type))
    {   $field = $field->study if $field->can('study');
        $raw   = $field->attribute('filename')
              || $field->attribute('file')
              || $field->attribute('name');
    }

    my $base;
    if(!defined $raw || !length $raw) {}
    elsif(index($raw, '?') >= 0)
    {   eval 'require Mail::Message::Field::Full';
        $base = Mail::Message::Field::Full->decode($raw);
    }
    else
    {   $base = $raw;
    }

    return $base
        unless @_;

    my $dir      = shift;
    my $filename = '';
    if(defined $base)
    {   $filename = basename $base;
        $filename =~ s/[^\w.-]//;
    }

    unless(length $filename)
    {   my $ext    = ($self->mimeType->extensions)[0] || 'raw';
        my $unique;
        for($unique = 'part-0'; 1; $unique++)
        {   my $out = File::Spec->catfile($dir, "$unique.$ext");
            open IN, '<', $out or last;  # does not exist: can use it
            close IN;
        }
        $filename = "$unique.$ext";
    }

    File::Spec->catfile($dir, $filename);
}

#------------------------------------------

=section Internals

=method getTransferEncHandler $type
Get the transfer encoder/decoder which is able to handle $type, or return
undef if there is no such handler.
=cut

my %transfer_encoder_classes =
 ( base64  => 'Mail::Message::TransferEnc::Base64'
 , binary  => 'Mail::Message::TransferEnc::Binary'
 , '8bit'  => 'Mail::Message::TransferEnc::EightBit'
 , 'quoted-printable' => 'Mail::Message::TransferEnc::QuotedPrint'
 , '7bit'  => 'Mail::Message::TransferEnc::SevenBit'
 );

my %transfer_encoders;   # they are reused.

sub getTransferEncHandler($)
{   my ($self, $type) = @_;

    return $transfer_encoders{$type}
        if exists $transfer_encoders{$type};   # they are reused.

    my $class = $transfer_encoder_classes{$type};
    return unless $class;

    eval "require $class";
    confess "Cannot load $class: $@\n" if $@;

    $transfer_encoders{$type} = $class->new;
}

=ci_method addTransferEncHandler $name, <$class|$object>
Relate the NAMEd transfer encoding to an OBJECTs or object of the specified
$class.  In the latter case, an object of that $class will be created on the
moment that one is needed to do encoding or decoding.

The $class or $object must extend M<Mail::Message::TransferEnc>.  It will
replace existing class and object for this $name.

Why aren't you contributing this class to MailBox?

=cut

sub addTransferEncHandler($$)
{   my ($this, $name, $what) = @_;

    my $class;
    if(ref $what)
    {   $transfer_encoders{$name} = $what;
        $class = ref $what;
    }
    else
    {   delete $transfer_encoders{$name};
        $class = $what;
    }

    $transfer_encoder_classes{$name} = $class;
    $this;
}

1;
