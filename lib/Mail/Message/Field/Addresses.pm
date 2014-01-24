use strict;
use warnings;

package Mail::Message::Field::Addresses;
use base 'Mail::Message::Field::Structured';

use Mail::Message::Field::AddrGroup;
use Mail::Message::Field::Address;
use List::Util 'first';

=chapter NAME

Mail::Message::Field::Addresses - Fields with e-mail addresses

=chapter SYNOPSIS

  my $cc = Mail::Message::Field::Full->new('Cc');
  my $me = Mail::Message::Field::Address->parse('"Test" <test@mail.box>')
     or die;

  my $other = Mail::Message::Field::Address->new(phrase => 'Other'
     , address => 'other@example.com')
     or die;

  $cc->addAddress($me);
  $cc->addAddress($other, group => 'them');
  $cc->addAddress(phrase => 'third', address => 'more@any.museum'
    , group => 'them');

  my $group = $cc->addGroup(name => 'collegues');
  $group->addAddress($me);
  $group->addAddress(phrase => "You", address => 'you@example.com');

  my $msg = Mail::Message->build(Cc => $cc);
  print $msg->string;

  my $g  = M<Mail::Message::Field::AddrGroup>->new(...);
  $cc->addGroup($g);

=chapter DESCRIPTION

All header fields which contain e-mail addresses only.  Not all address
fields have the same possibilities, but they are all parsed the same:
you never know how broken the applications are which produce those
messages.

When you try to create constructs which are not allowed for a certain
kind of field, you will be warned.

=chapter METHODS

=c_method new
=default attributes <ignored>
=cut

#------------------------------------------
# what is permitted for each field.

my $address_list = {groups => 1, multi => 1};
my $mailbox_list = {multi => 1};
my $mailbox      = {};

my %accepted     =    # defaults to $address_list
  ( from       => $mailbox_list
  , sender     => $mailbox
  );

sub init($)
{   my ($self, $args) = @_;

    $self->{MMFF_groups}   = [];

    ( my $def = lc $args->{name} ) =~ s/^resent\-//;
    $self->{MMFF_defaults} = $accepted{$def} || $address_list;

    my ($body, @body);
    if($body = $args->{body})
    {   @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
    }

    if(@body > 1 || ref $body[0])
    {   $self->addAddress($_) foreach @body;
        delete $args->{body};
    }

    $self->SUPER::init($args) or return;
    $self;
}

#------------------------------------------

=section Access to the content

=method addAddress [$address], %options
Add an $address to the field.  The addresses are organized in groups.  If no
group is specified, the default group is taken to store the address in.  If
no $address is specified, the option must be sufficient to create a
M<Mail::Message::Field::Address> from.  See the %options of
M<Mail::Message::Field::Address::new()>.

=option  group STRING
=default group C<''>

=cut

sub addAddress(@)
{   my $self  = shift;
    my $email = @_ && ref $_[0] ? shift : undef;
    my %args  = @_;
    my $group = delete $args{group} || '';

    $email = Mail::Message::Field::Address->new(%args)
        unless defined $email;

    my $set = $self->group($group) || $self->addGroup(name => $group);
    $set->addAddress($email);
    $email;
}

=method addGroup $group|%options
Add a group of addresses to this field.  A $group can be specified, which
is a M<Mail::Message::Field::AddrGroup> object, or one is created for you
using the %options.  The group is returned.

=option  name STRING
=default name C<''>

=cut

sub addGroup(@)
{   my $self  = shift;
    my $group = @_ == 1 ? shift
              : Mail::Message::Field::AddrGroup->new(@_);

    push @{$self->{MMFF_groups}}, $group;
    $group;
}

=method group $name
Returns the group of addresses with the specified $name, or C<undef>
if it does not exist.  If $name is C<undef>, then the default groep
is returned.
=cut

sub group($)
{   my ($self, $name) = @_;
    $name = '' unless defined $name;
    first { lc($_->name) eq lc($name) } $self->groups;
}

=method groups
Returns all address groups which are defined in this field.  Each
element is a M<Mail::Message::Field::AddrGroup> object.
=cut

sub groups() { @{shift->{MMFF_groups}} }

=method groupNames
Returns a list with all group names which are defined.
=cut

sub groupNames() { map {$_->name} shift->groups }

=method addresses
Returns a list with all addresses defined in any group of addresses:
all addresses which are specified on the line.  The addresses are
M<Mail::Message::Field::Address> objects.

=example
 my @addr = $field->addresses;

=cut

sub addresses() { map {$_->addresses} shift->groups }

=method addAttribute ...
Attributes are not supported for address fields.

=error No attributes for address fields.
Is is not possible to add attributes to address fields: it is not permitted
by the RFCs.
=cut

sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for address fields.');
    $self;
}

#------------------------------------------

=section Parsing
=cut

sub parse($)
{   my ($self, $string) = @_;
    my ($group, $email) = ('', undef);
    $string =~ s/\s+/ /gs;

    while(1)
    {   (my $comment, $string) = $self->consumeComment($string);

        if($string =~ s/^\s*\;//s ) { $group = ''; next }  # end group
        if($string =~ s/^\s*\,//s ) { next }               # end address

        (my $email, $string) = $self->consumeAddress($string);
        if(defined $email)
        {   # Pattern starts with e-mail address
            ($comment, $string) = $self->consumeComment($string);
            $email->comment($comment) if defined $comment;
        }
        else
        {   # Pattern not plain address
            my $real_phrase = $string =~ m/^\s*\"/;
            (my $phrase, $string) = $self->consumePhrase($string);

            if(defined $phrase)
            {   ($comment, $string) = $self->consumeComment($string);

                if($string =~ s/^\s*\://s )
                {   $group = $phrase;
                    # even empty groups must appear
                    $self->addGroup(name=>$group) unless $self->group($group);
                    next;
                }
            }

            my $angle;
            if($string =~ s/^\s*\<([^>]*)\>//s) { $angle = $1 }
            elsif($real_phrase)
            {   $self->log(ERROR => "Ignore unrelated phrase `$1'")
                    if $string =~ s/^\s*\"(.*?)\r?\n//;
                next;
            }
            elsif(defined $phrase)
            {   ($angle = $phrase) =~ s/\s+/./g;
                undef $phrase;
            }

            ($comment, $string) = $self->consumeComment($string);

            # remove obsoleted route info.
            return 1 unless defined $angle;
            $angle =~ s/^\@.*?\://;

            ($email, $angle) = $self->consumeAddress($angle
              , phrase => $phrase, comment => $comment);
        }

        $self->addAddress($email, group => $group) if defined $email;
        return 1 if $string =~ m/^\s*$/s;
   }

   $self->log(WARNING => 'Illegal part in address field '.$self->Name.
        ": $string\n");

   0;
}

sub produceBody()
{  my @groups = sort {$a->name cmp $b->name} shift->groups;

   @groups     or return '';
   @groups > 1 or return $groups[0]->string;

   my $plain
    = $groups[0]->name eq '' && $groups[0]->addresses
    ? (shift @groups)->string.','
    : '';

   join ' ', $plain, map({$_->string} @groups);
}

=method consumeAddress STRING, %options
Try to destilate address information from the STRING.   Returned are
an address B<object> and the left-over string.  If no address was found,
the first returned value is C<undef>.
=cut

sub consumeAddress($@)
{   my ($self, $string, @options) = @_;

    my ($local, $shorter, $loccomment) = $self->consumeDotAtom($string);
    $local =~ s/\s//g if defined $local;

    return (undef, $string)
        unless defined $local && $shorter =~ s/^\s*\@//;
  
    (my $domain, $shorter, my $domcomment) = $self->consumeDomain($shorter);
    return (undef, $string) unless defined $domain;

    # loccomment and domcomment ignored
    my $email   = Mail::Message::Field::Address
        ->new(username => $local, domain => $domain, @options);

    ($email, $shorter);
}

=method consumeDomain STRING
Try to get a valid domain representation from STRING.  Returned are the
domain string as found (or C<undef>) and the rest of the string.
=cut

sub consumeDomain($)
{   my ($self, $string) = @_;

    return ($self->stripCFWS($1), $string)
        if $string =~ s/\s*(\[(?:[^[]\\]*|\\.)*\])//;

    my ($atom, $rest, $comment) = $self->consumeDotAtom($string);
    $atom =~ s/\s//g if defined $atom;
    ($atom, $rest, $comment);
}

#------------------------------------------

=section Error handling
=cut

1;
