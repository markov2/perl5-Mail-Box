
package Mail::Message::Head::FieldGroup;
use base 'Mail::Reporter';

use strict;
use warnings;

=chapter NAME

Mail::Message::Head::FieldGroup - a sub set of fields in a header

=chapter SYNOPSIS

Never instantiated directly.

=chapter DESCRIPTION

Some fields have a combined meaning: a set of fields which represent
one intermediate step during the transport of the message (a
I<resent group>, implemented in M<Mail::Message::Head::ResentGroup>), 
fields added by mailing list software (implemented in
M<Mail::Message::Head::ListGroup>), or fields added by Spam detection
related software (implemented by M<Mail::Message::Head::SpamGroup>).
Each set of fields can be extracted or added as group with objects
which are based on the implementation in this class.

=chapter METHODS

=section Constructors

=c_method new $fields, %options

Construct an object which maintains one set of header $fields.  The
$fields may be specified as C<Mail::Message::Field> objects or as key-value
pairs.  The %options and $fields (as key-value pair) can be mixed: they are
distinguished by their name, where the fields always start with a capital.
The field objects must aways lead the %options.

=option  head HEAD
=default head C<undef>

The header HEAD object is used to store the grouped fields in.
If no header is specified, a M<Mail::Message::Head::Partial> is created
for you.  If you wish to scan the existing fields in a header, then use
the M<from()> method.

=option  version STRING
=default version C<undef>
Version number for the software which produced the fields.

=option  software STRING
=default software C<undef>
Name of the software which produced the fields.

=option  type STRING
=default type C<undef>
Group name for the fields.  Often the same, or close
to the same STRING, as the C<software> option contains.

=cut

sub new(@)
{   my $class = shift;

    my @fields;
    push @fields, shift while ref $_[0];

    $class->SUPER::new(@_, fields => \@fields);
}

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $head = $self->{MMHF_head}
      = $args->{head} || Mail::Message::Head::Partial->new;

    $self->add($_)                            # add specified object fields
        foreach @{$args->{fields}};

    $self->add($_, delete $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    $self->{MMHF_version}  = $args->{version}  if defined $args->{version};
    $self->{MMHF_software} = $args->{software} if defined $args->{software};
    $self->{MMHF_type}     = $args->{type}     if defined $args->{type};

    $self->{MMHF_fns}      = [];
    $self;
}

#------------------------------------------

=ci_method implementedTypes
Returns a list of strings containing all possible return values for
M<type()>.

=cut

sub implementedTypes() { shift->notImplemented }

#------------------------------------------

=method from $head|$message

Create a group of fields based on the specified $message or message $head.
This may return one or more of the objects, which depends on the
type of group.  Mailing list fields are all stored in one object,
where resent and spam groups can appear more than once.

=cut

sub from($) { shift->notImplemented }

#------------------------------------------

=method clone

Make a copy of this object.  The collected fieldnames are copied and the
list type information.  No deep copy is made for the header: this is
only copied as reference.

=cut

sub clone()
{   my $self = shift;
    my $clone = bless %$self, ref $self;
    $clone->{MMHF_fns} = [ $self->fieldNames ];
    $clone;
}

#------------------------------------------

=section The header

=method head

Returns the header object, which includes these fields.

=cut

sub head() { shift->{MMHF_head} }

#------------------------------------------

=method attach $head
Add a group of fields to a message $head.  The fields will be cloned(!)
into the header, so that the field group object can be used again.

=example attaching a list group to a message

 my $lg = Mail::Message::Head::ListGroup->new(...);
 $lg->attach($msg->head);
 $msg->head->addListGroup($lg);   # same

 $msg->head->addSpamGroup($sg);   # also implemented with attach
=cut

sub attach($)
{   my ($self, $head) = @_;
    $head->add($_->clone) for $self->fields;
    $self;
}

#------------------------------------------

=method delete

Remove all the header lines which are combined in this fields group,
from the header.

=cut

sub delete()
{   my $self   = shift;
    my $head   = $self->head;
    $head->removeField($_) foreach $self->fields;
    $self;
}

#------------------------------------------

=method add <$field, $value> | $object

Add a field to the header, using the field group.  When the field group
is already attached to a real message header, it will appear in that
one as well as being registed in this set.  If no header is defined,
the field only appears internally.

=example adding a field to a detached list group

 my $this = Mail::Message::Head::ListGroup->new(...);
 $this->add('List-Id' => 'mailbox');
 $msg->addListGroup($this);
 $msg->send;

=example adding a field to an attached list group

 my $lg = Mail::Message::Head::ListGroup->from($msg);
 $lg->add('List-Id' => 'mailbox');

=cut

sub add(@)
{   my $self = shift;
    my $field = $self->head->add(@_) or return ();
    push @{$self->{MMHF_fns}}, $field->name;
    $self;
}

#------------------------------------------

=method fields
Return the fields which are defined for this group.

=cut

sub fields()
{   my $self = shift;
    my $head = $self->head;
    map { $head->get($_) } $self->fieldNames;
}

#------------------------------------------

=method fieldNames
Return the names of the fields which are used in this group.

=cut

sub fieldNames() { @{shift->{MMHF_fns}} }

#------------------------------------------

=method addFields [$fieldnames]
Add some $fieldnames to the set.

=cut

sub addFields(@)
{   my $self = shift;
    my $head = $self->head;

    push @{$self->{MMHF_fns}}, @_;
    @_;
}

#------------------------------------------

=section Access to the header

=method version 
Returns the version number of the software used to produce the fields.
Some kinds of software do leave such a trace, other cases will return
C<undef>

=cut

sub version() { shift->{MMHF_version} }

#------------------------------------------

=method software
Returns the name of the software as is defined in the headers.  The may
be slightly different from the return value of M<type()>, but usually
not too different.

=cut

sub software() { shift->{MMHF_software} }

#------------------------------------------

=method type
Returns an abstract name for the field group; which software is
controling it.  C<undef> is returned in case the type is not known.
Valid names are group type dependent: see the applicable manual
pages.  A list of all types can be retrieved with M<implementedTypes()>.

=cut

sub type() { shift->{MMHF_type} }

#------------------------------------------

=section Internals

=method detected $type, $software, $version
Sets the values for the field group type, software, and version,
prossibly to C<undef>.

=cut

sub detected($$$)
{   my $self = shift;
    @$self{ qw/MMHF_type MMHF_software MMHF_version/ } = @_;
}

#------------------------------------------

=method collectFields [$name]

Scan the header for fields which are usually contained in field group
with the specified $name.  For mailinglist groups, you can not specify
a $name: only one set of headers will be found (all headers are considered
to be produced by exactly one package of mailinglist software).

This method is automatically called when a field group is
constructed via M<from()> on an existing header or message.

Returned are the names of the list header fields found, in scalar
context the amount of fields.  An empty list/zero indicates that there
was no group to be found.

Please warn the author of MailBox if you see that to few
or too many fields are included.

=cut

sub collectFields(;$) { shift->notImplemented }

#------------------------------------------

=section Error handling

=method print [$fh]

Print the group to the specified $fh or GLOB.  This is probably only
useful for debugging purposed.  The output defaults to the selected file
handle.

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || select;
    $_->print($out) foreach $self->fields;
}

#------------------------------------------

=method details

Produce information about the detected/created field group, which may be
helpful during debugging.  A nicely formatted string is returned.

=cut

sub details()
{   my $self     = shift;
    my $type     = $self->type || 'Unknown';

    my $software = $self->software;
    undef $software if defined($software) && $type eq $software;
    my $version  = $self->version;
    my $release
      = defined $software
      ? (defined $version ? " ($software $version)" : " ($software)")
      : (defined $version ? " ($version)"           : '');

    my $fields   = scalar $self->fields;
    "$type $release, $fields fields";
}

#------------------------------------------

1;
