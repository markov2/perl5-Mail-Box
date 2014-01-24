use strict;
use warnings;

package Mail::Message::Field::AddrGroup;
use base 'User::Identity::Collection::Emails';

=chapter NAME

Mail::Message::Field::AddrGroup - A group of Mail::Message::Field::Address objects

=chapter SYNOPSIS

 my $g = Mail::Message::Field::AddrGroup->new(name => 'name');

 my $a = Mail::Message::Field::Address->new(...);
 $g->addAddress($a);
 
 my $f = Mail::Message::Field::Addresses->new;
 $f->addGroup($g);

=chapter DESCRIPTION

An address group collects a set of e-mail addresses (in this case they
are M<Mail::Message::Field::Address> objects).

=chapter OVERLOADED

=overload stringification

Returns the M<string()> value.

=cut

use overload '""' => 'string';

#------------------------------------------

=chapter METHODS

=method string

Returns the address group as string.  When no name is specified, it will
only be a comma separated list of addresses.  With a name, the groups
name will be prepended and a semi-colon appended.  When no addresses
where included and there is no name, then C<undef> is returned.

=cut

sub string()
{   my $self = shift;
    my $name = $self->name;
    my @addr = sort map {$_->string} $self->addresses;

    local $" = ', ';

      length $name  ? "$name: @addr;"
    : @addr         ? "@addr"
    :                 '';
}

#------------------------------------------

=section Constructors

=method coerce $object

Coerce an $object into a M<Mail::Message::Field::AddrGroup>.  Currently,
you can only coerce M<User::Identity::Collection::Emails> (which is
the base class for this one) into this one.

=error Cannot coerce a $type into a Mail::Message::Field::AddrGroup

=cut

sub coerce($@)
{  my ($class, $addr, %args) = @_;

   return () unless defined $addr;

   if(ref $addr)
   {  return $addr if $addr->isa($class);

      return bless $addr, $class
          if $addr->isa('User::Identity::Collection::Emails');
   }

   $class->log(ERROR => "Cannot coerce a ".(ref($addr)|'string').
                        " into a $class");
   ();
}


#------------------------------------------

=section Addresses

=method addAddress STRING|$address|%options

Add one e-mail address to the list which is maintained in the group. This
is a wrapper around M<addRole()> adding flexibility on how addresses
are specified.  An $address can be anything which is acceptable for
M<Mail::Message::Field::Address::coerce()> or a list of options which
will create such an object.

=examples of adding an address to an address group

 my @data = (full_name => "Myself", address => 'me@tux.org');
 $group->addAddress(@data);

 my $addr = M<Mail::Message::Field::Address>->new(@data);
 $group->addAddress(@data);

 my $ma = Mail::Address->new(...);
 $group->addAddress($ma);

=cut

sub addAddress(@)
{   my $self  = shift;

    my $addr
     = @_ > 1    ? Mail::Message::Field::Address->new(@_)
     : !$_[0]    ? return ()
     :             Mail::Message::Field::Address->coerce(shift);

    $self->addRole($addr);
    $addr;
}

=method addresses
Returns all addresses defined in this group.  The addresses will be
ordered alphabetically to make automated testing possible: roles are
stored in a hash, so have an unpredictable order by default.

=example getting all addresses from a group

 my @addrs = $group->addresses;
 my @addrs = map { $_->address } $self->roles; #same

=cut

# roles are stored in a hash, so produce
sub addresses() { shift->roles }

#------------------------------------------

=section Error handling

=cut

1;
