use strict;
use warnings;

package Mail::Message::Field::Addresses;
use base 'Mail::Message::Field::Full';

use Mail::Message::Field::AddrGroup;
use Mail::Message::Field::Address;
use List::Util 'first';

=head1 NAME

Mail::Message::Field::Addresses - Fields with e-mail addresses

=head1 SYNOPSIS

 my $f = Mail::Message::Field->new(Cc => 'Mail::Box <mailbox@overmeer.net>');

 my $g = Mail::Message::Field->new('Cc');
 $g->addAddress('Mail::Box <mailbox@overmeer.net>');
 $g->addAddress
   ( phrase  => 'Mail::Box'
   , email   => 'mailbox@overmeer.net'
   , comment => 'Our mailing list'     # deprecated, use phrase
   );

=head1 DESCRIPTION

All header fields which contain e-mail addresses only.  Not all address
fields have the same possibilities, but they are all parsed the same:
you never know how broken the applications are which produce those
messages.

When you try to create constructs which are not allowed for a certain
kind of field, you will be warned.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------
# what is permitted for each field.

my $address_list = {groups => 1, multi => 1};
my $mailbox_list = {multi => 1};
my $mailbox      = {};

my %accepted     =
 ( from       => $mailbox_list
 , sender     => $mailbox
 , 'reply-to' => $address_list
 , to         => $address_list
 , cc         => $address_list
 , bcc        => $address_list
 );


#------------------------------------------

=method new DATA

=default attributes    C<not accepted>
=default extra         C<not accepted>
=default is_structured 1

=examples

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{is_structured} = 1;

    my $name = $args->{name};
    if(my $body = $args->{body})
    {   my @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
#       $args->{body} = $self->encode(join(", ", @body), %$args);
    }
    else
    {   ($name, my $body) = split /\s*\:/, $name, 2;
        $args->{name} = $name;
        return () unless defined $body;
#       $args->{body} = $body;
    }

    $self->SUPER::init($args) or return;

    (my $def = lc $name) =~ s/^resent\-//;
    $self->{MMFF_defaults} = $accepted{$def} || {};
    $self->{MMFF_groups}   = [];
    
    $self;
}

#------------------------------------------

=method parse STRING

Parse the supplied address string, and store the found data in this
object.

=cut

sub parse($)
{   my ($self, $string) = @_;
    my ($group, $comment);

    while(1)
    {   ($comment, $string) = $self->consumeComment($string);

        if($string =~ s/^\s*\;// ) { undef $group; next }  # end group
        if($string =~ s/^\s*\,// ) { next }                # end address

        (my $phrase, $string) = $self->consumePhrase($string);
        if(defined $phrase)
        {   ($comment, $string) = $self->consumeComment($string);
            if($string =~ s/\s*\:// ) { $group = $phrase; next }

            if($string =~ s/\@// )
            {   (my $domain, $string, my $domcomment)
                   = $self->consumeDomain($string);
                ($comment, $string) = $self->consumeComment($string);

                $self->addAddress(local => $phrase, group => $group
                   , comment => $comment, domcomment => $domcomment);

                next;
            }
        }

        if($string =~ s/^\s*\<([^>]*)\>//)
        {   # remove obsoleted route info.
            (my $angle = $1) =~ s/^\@.*?\://;

            my $email = $self->consumeAddress($angle);
            $email->name($phrase)     if defined $phrase;
            $email->comment($comment) if defined $comment;

            ($comment, $string) = $self->consumeComment($string);
            $email->comment($comment) if defined $comment;

            $self->addAddress($email);
        }

        return 1 if m/^\s*$/;

        $self->log(WARNING => 'Illegal part in address field '.$self->Name.
                    ": $string\n");
        return 0;
    }
}


#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

=method addAddress [ADDRESS], OPTIONS

Add an ADDRESS to the field.  The addresses are organized in groups.  If no
group is specified, the default group is taken to store the address in.  If
no ADDRESS is specified, the option must be sufficient to create a
Mail::Message::Field::Address from.  See the OPTIONS of
Mail::Message::Field::Address::new().

=option  group STRING
=default group ''

=cut

sub addAddress(@)
{   my $self  = shift;
    my $email = @_ && ref $_[0] ? shift : undef;
    my %args  = @_;
    my $group = delete $args{group};

    $email = Mail::Message::Field::Address->new(%args)
        unless defined $email;

    my $set = $self->group($group) || $self->addGroup(name => $group);
    $set->addAddress($email);
}

#------------------------------------------

=method addGroup GROUP|OPTIONS

Add a group of addresses to this field.  A GROUP can be specified, which
is a Mail::Message::Field::AddrGroup object, or one is created for you
using the OPTIONS.  The group is returned.

=option  name STRING
=default name ''

=cut

sub addGroup(@)
{   my $self  = shift;

    my $group = @_ == 1 ? shift
              : Mail::Message::Field::AddrGroup->new(@_);

    push @{$self->{MMFF_groups}}, $group;
    $group;
}

#------------------------------------------

=method group NAME

Returns the group of addresses with the specified NAME, or C<undef>
if it does not exist.  If NAME is C<undef>, then the default groep
is returned.

=cut

sub group($)
{   my ($self, $name) = @_;
    $name = '' unless defined $name;
    first { lc($_->name) eq lc($name) } $self->groups;
}

#------------------------------------------

=method groups

Returns all address groups which are defined in this field.  Each
element is a Mail::Message::Field::AddrGroup object.

=cut

sub groups() { @{shift->{MMFF_groups}} }

#------------------------------------------

=method groupNames

Returns a list with all group names which are defined.

=cut

sub groupNames() { map {$_->name} shift->groups }

#------------------------------------------

=method addresses

Returns a list with all addresses defined in any group of addresses:
all addresses which are specified on the line.  The addresses are
Mail::Message::Field::Address objects.

=example

 my @addr = $field->addresses;

=cut

sub addresses() { map {$_->addresses} shift->groups }

#------------------------------------------

=method addAttribute ...

Attributes are not supported for address fields.

=cut

sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for address fields.');
    $self;
}

#------------------------------------------

=method addExtra ...

Extras are not permitted in address fields.

=cut

sub addExtra($@)
{   my $self = shift;
    $self->log(ERROR => 'No extras in address fields.');
    $self;
}

#------------------------------------------

=method consumeAddress STRING

Try to destilate address information from the STRING.   Returned are
an address B<object> and the left-over string.  If no address was found,
the first returned value is C<undef>.

=cut

sub consumeAddress($)
{   my ($self, $string) = @_;

    (my $local, $string, my $comment) = $self->consumeDotAtom($string);
    $local =~ s/\s//g;

    return (undef, $_[0])
        unless defined $local && $string =~ s/^\s*\@//;
  
    (my $domain, $string, my $domcomment) = $self->consumeDomain($string);
    return (undef, $_[0]) unless defined $domain;

    my $email   = Mail::Message::Field::Address->new
     ( local => $local, domain => $domain, comment => $comment
     , domcomment => $domcomment );

    ($email, $string);
}

#------------------------------------------

=method consumeDomain STRING

Try to get a valid domain representation from STRING.  Returned are the
domain string as found (or C<undef>) and the rest of the string.

=cut

sub consumeDomain($)
{   my ($self, $string) = @_;

    return ($self->stripCFWS($1), $string)
        if $string =~ s/\s*(\[(?:[^[]\\]*|\\.)*\])//;

    my ($atom, $rest, $comment) = $self->consumeDotAtom($string);
    $atom =~ s/\s//g;
    ($atom, $rest, $comment);
}

#------------------------------------------

1;
