
use strict;
use warnings;

package Mail::Message::Body;   ###
use base 'Mail::Reporter';

use Carp;

use MIME::Types;
my MIME::Types $mime_types;

our $VERSION = 2.00_19;

=head1 NAME

Mail::Message::Body::Encode - organize general message encodings

=head1 CLASS HIERARCHY

 Mail::Message::TransferEnc
 is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message $msg = ...;
 my $decoded = $msg->decoded;
 my $encoded = $msg->encode(mime_type => 'image/gif', transfer => 'base64');

 my $body = $msg->body;
 my $decoded = $body->decoded;
 my $encoded = $body->encode(transfer => '7bit');

=head1 DESCRIPTION

Manages the message's body encodings and decodings on request of the
main program.  This package adds functionality to the C<Mail::Message::Body>
class when the C<decoded> or C<encode> method is called.

Three types of encodings are handled (in the right order)

=over 4

=item * transfer encoding

Messages transmitted over Internet have to be plain ASCII.  Complicated
characters and binary files (like images and archives) must be encoded
during transmission to an ASCII representation.

The implementation of the required encoders and decoders is found in
the C<Mail::Message::TransferEnc> set of packages.  The related
manual page losts the transfer encodings which are supported.

=item * mime-type translation

=item * charset conversion

=back

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Encode> objects:

      check                                encoded
      encode OPTIONS                       isBinary

The extra methods for extension writers:

      addTransferEncHandler NAME,...       getTransferEncHandler TYPE

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item encode OPTIONS

Encode (translate) a C<Mail::Message::Body> object into a different format.
See the DESCRIPTION above.  Options which are not specified will not trigger
conversions.

 OPTION            DESCRIBED IN         DEFAULT
 charset           Mail::Message::Body  undef
 mime_type         Mail::Message::Body  undef
 result_type       Mail::Message::Body  <same as source>
 transfer_encoding Mail::Message::Body  undef

=over 4

=item * mime_type =E<gt> STRING|FIELD

Convert into the specified mime type, which can be specified as STRING
or FIELD.  The FIELD is a C<Mail::Message::Field>, and the STRING is
converted in such object before use.

=item * charset =E<gt> STRING

=item * result_type =E<gt> CLASS

The type of body to be created when the body is changed to fulfil the request
on re-coding.  Also the intermediate stages in the translation process (if
needed) will use this type. CLASS must extend C<Mail::Message::Body>.

=item * transfer_encoding =E<gt> STRING|FIELD

=back

=cut

sub encode(@)
{   my ($self, %args) = @_;

    # simplify the arguments

    my $type_from = $self->type;
    my $type_to   = $args{mime_type} || $type_from->clone;
    $type_to = Mail::Message::Field->new('Content-Type' => $type_to)
        unless ref $type_to;

    if(my $charset = delete $args{charset})
    {   $type_to->attribute(charset => $charset);
    }

    my $transfer = $args{transfer_encoding} || $self->transferEncoding->clone;
    $transfer    = Mail::Message::Field->new('Content-Transfer-Encoding' =>
         $transfer) unless ref $transfer;

    # What will we do?
#   my $mime_was  = lc $type_from;
#   my $mime_to   = lc $type_to;

# If possible, update unify() too.
#   my $char_was  = $type_from->attribute('charset');
#   my $char_to   = $type_to->attribute('charset');

    my $trans_was = lc $self->transferEncoding;
    my $trans_to  = lc $transfer;

#warn "Translate ($mime_was, $char_was, $trans_was) -> ($mime_to, $char_to, $trans_to)\n";

    #
    # The only translations implemented now is content transfer encoding.
    #

#warn "Translate ($trans_was) -> ($trans_to)\n";
    return $self if $trans_was eq $trans_to;

    my $bodytype  = $args{result_type} || ref $self;

    my $decoded;
    if($trans_was eq 'none') {$decoded = $self}
    elsif(my $decoder = $self->getTransferEncHandler($trans_was))
    {   $decoded = $decoder->decode($self, result_type => $bodytype) }
    else
    {   $self->log(WARNING => 'No decoder for $trans_was.');
        return $self;
    }

    my $encoded;
    if($trans_to eq 'none') {$encoded = $decoded}
    elsif(my $encoder = $self->getTransferEncHandler($trans_to))
    {   $encoded = $encoder->encode($decoded, result_type => $bodytype) }
    else
    {   $self->log(WARNING => 'No encoder for $trans_to.');
        return $decoded;
    }

    return $encoded;
}

#------------------------------------------

=item check

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

    my $encoding = $self->transferEncoding->body;
    return $self if $encoding eq 'none';

    my $encoder  = $self->getTransferEncHandler($encoding);
    $encoder->check($self);
}

#------------------------------------------

=item encoded

Encode the body to a format what is acceptable to transmit or write to
a folder file.  This returns the body where this method was called
upon when everything was already prepared, or a new encoded body
otherwise.  In either case, the body is checked.

=cut

sub encoded()
{   my $self = shift;

    return $self->check
        unless $self->transferEncoding eq 'none';

    $mime_types ||= MIME::Types->new;

    my $mime = $mime_types->type($self->type->body);
    $self->encode(transfer_encoding =>
         defined $mime ? $mime->encoding : 'base64');
}

#------------------------------------------

=item isBinary

Returns true when the un-encoded message is binary data.  This information
is retreived from knowledge provided by L<MIME::Types>.

=cut

sub isBinary()
{   my $self = shift;
    $mime_types ||= MIME::Types->new(only_complete => 1);
    my $mime = $mime_types->type($self->type->body);
    !defined $mime || $mime->isBinary;
}
 
#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item unify BODY

Unify the type of the given BODY objects with the type of the called
body.  C<undef> is returned when unification is impossible.  If the
bodies have the same settings, the BODY object is returned unchanged.

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

# Character transformation not possible yet.
#   my $want_charset= $mime->attribute('charset')    || '';
#   my $got_charset = $newmime->attribute('charset') || '';
#   return unless $want_charset eq $got_charset;

    $encoded;
}

#------------------------------------------

=item getTransferEncHandler TYPE

Get the transfer encoder/decoder which is able to handle TYPE, or return
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

#------------------------------------------

=item addTransferEncHandler NAME, CLASS|OBJECT

(Class or instance method)
Relate the NAMEd transfer encoding to an OBJECTs or object of the specified
CLASS.  In the latter case, an object of that CLASS will be created on the
moment that one is needed to do encoding or decoding.

The CLASS or OBJECT must extend C<Mail::Message:TransferEnc>.  It will
replace existing class and object for this NAME.

Why aren't you contributing this class to C<Mail::Box>?

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

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_19.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
