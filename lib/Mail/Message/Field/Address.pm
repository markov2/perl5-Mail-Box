use strict;
use warnings;

package Mail::Message::Field::Address;
use base 'Mail::Identity';

use Mail::Message::Field::Addresses;
use Mail::Message::Field::Full;
my $format = 'Mail::Message::Field::Full';

=chapter NAME

Mail::Message::Field::Address - One e-mail address

=chapter SYNOPSIS

 my $addr = Mail::Message::Field::Address->new(...);

 my $ui   = User::Identity->new(...);
 my $addr = Mail::Message::Field::Address->coerce($ui);

 my $mi   = Mail::Identity->new(...);
 my $addr = Mail::Message::Field::Address->coerce($mi);

 print $addr->address;
 print $addr->fullName;   # possibly unicode!
 print $addr->domain;

=chapter DESCRIPTION

Many header fields can contain e-mail addresses.  Each e-mail address
can be represented by an object of this class.  These objects will
handle interpretation and character set encoding and decoding for you.

=chapter OVERLOADED

=overload stringification

When the object is used in string context, it will return the encoded
representation of the e-mail address, just like M<string()> does.

=overload boolean

The object used as boolean will always return C<true>

=overload string $comparison

Two address objects are the same when their email addresses are the
same.

=cut

use overload
      '""' => 'string'
    , bool => sub {1}
    , cmp  => sub { lc($_[0]->address) eq lc($_[1]) }
    ;

#------------------------------------------

=chapter METHODS

=section Constructors

=method coerce <STRING|$object>, %options

Try to coerce the $object into a C<Mail::Message::Field::Address>.
In case of a STRING, it is interpreted as an email address.

The %options are passed to the object creation, and overrule the values
found in the $object.  The result may be C<undef> or a newly created
object.  If the $object is already of the correct type, it is returned
unmodified.

The $object may currently be a M<Mail::Address>, a M<Mail::Identity>, or
a M<User::Identity>.  In case of the latter, one of the user's addresses
is chosen at random.

=error Cannot coerce a $type into a Mail::Message::Field::Address

When addresses are specified to be included in header fields, they may
be coerced into M<Mail::Message::Field::Address> objects first.  What
you specify is not accepted as address specification.  This may be an
internal error.

=cut

sub coerce($@)
{  my ($class, $addr, %args) = @_;
   return () unless defined $addr;

   ref $addr or return $class->parse($addr);
   $addr->isa($class) and return $addr;

   my $from = $class->from($addr, %args);

   Mail::Reporter->log(ERROR => "Cannot coerce a ".ref($addr)." into a $class"),
      return () unless defined $from;

   bless $from, $class;
}

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{MMFA_encoding} = delete $args->{encoding};
    $self;
}

=method parse STRING

Parse the string for an address.  You never know whether one or more
addresses are specified on a line (often applications are wrong), therefore,
the STRING is first parsed for as many addresses as possible and then the
one is taken at random.

=cut

sub parse($)
{   my $self   = shift;
    my $parsed = Mail::Message::Field::Addresses->new('To' => shift);
    defined $parsed ? ($parsed->addresses)[0] : ();
}

#------------------------------------------

=section Accessors

=method encoding
Character-set encoding, like 'q' and 'b', to be used when non-ascii
characters are to be transmitted.
=cut

sub encoding() {shift->{MMFA_encoding}}

#------------------------------------------

=section Access to the content

=method string
Returns an RFC compliant e-mail address, which will have character
set encoding if needed.  The objects are also overloaded to call
this method in string context.

=example

 print $address->string;
 print $address;          # via overloading

=cut

sub string()
{   my $self  = shift;
    my @opts  = (charset => $self->charset, encoding => $self->encoding);
       # language => $self->language

    my @parts;
    my $name    = $self->phrase;
    push @parts, $format->createPhrase($name, @opts) if defined $name;

    my $address = $self->address;
    push @parts, @parts ? '<'.$address.'>' : $address;

    my $comment = $self->comment;
    push @parts, $format->createComment($comment, @opts) if defined $comment;

    join ' ', @parts;
}

1;
