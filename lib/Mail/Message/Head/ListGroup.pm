
use strict;

package Mail::Message::Head::ListGroup;
use base 'Mail::Reporter';

use Mail::Message::Field::Fast;

use Scalar::Util 'weaken';
use List::Util   'first';
use Sys::Hostname;

=chapter NAME

Mail::Message::Head::ListGroup - mailinglist related header fields

=chapter SYNOPSIS

 my $lg = Mail::Message::Head::ListGroup->new(head => $head, ...);
 $head->addListGroup($lg);

 my $lg = $head->addListGroup(...);

 $lg->delete;

=chapter DESCRIPTION

A I<list group> is a set of header fields which are added by mailing-list
managing software.  This class contains various kinds of knowledge about
that software.

The knowledge and test messages which are used to initially implement
this module is taken from M<Mail::ListDetector>, written by
Michael Stevens <mailto:michael@etla.org>.  The logic is redesigned to
add flexibility and use the powerful MailBox features.

=chapter METHODS

=section Constructors

=c_method new FIELDS, OPTIONS

Construct an object which maintains one set of mailing list headers.  The
FIELDS may be specified as C<Mail::Message::Field> objects or as key-value
pairs.  The OPTIONS and FIELDS (as key-value pair) can be mixed: they are
distinguished by their name, where the fields always start with a capital.
The field objects must aways lead the OPTIONS.

=option  head HEAD
=default head C<undef>

The header HEAD object is used to store the list fields in.  If no header
is specified, a M<Mail::Message::Head::Partial> is created for you.  If
you wish to scan the existing fields in a header, then use the M<from()>
method.

=option  version STRING
=default version C<undef>
Version number for the mailing list software.

=option  software STRING
=default software C<undef>
Name of the software which maintains the mailing list.

=option  rfc 'rfc2918'|'rfc2369'
=default rfc C<undef>
Defines the mailing list software follows an rfc.

=option  listname STRING
=default listname <derived from address>
A short textual representation of the mailing-list.

=option  address STRING|OBJECT
=default address C<undef>
Address of the mailing list, which may be specified as STRING
or e-mail containing object (a M<Mail::Address> or M<Mail::Identity>.
In any case, the data is converted into a M<Mail::Identity>.

=option  type STRING
=default type C<undef>
Group name for the mailing list software.  Often the same, or close
to the same STRING, as the C<software> option contains.

=error Cannot convert "$string" into an address object
The M<new(address)> is coerced into a M<Mail::Message::Field::Address>,
which fails.  Have a look at M<Mail::Message::Field::Address::coerce()>
to see what valid arguments are.

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

    my $head = $self->{MMHL_head}
      = $args->{head} || Mail::Message::Head::Partial->new;

    $self->add($_)                     # add specified object fields
        foreach @{$args->{fields}};

    $self->add($_, $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    my $address = $args->{address};
       if(!defined $address) { ; }
    elsif(!ref $address || !$address->isa('Mail::Message::Field::Address'))
    {   require Mail::Message::Field::Address;
        my $mi   = Mail::Message::Field::Address->coerce($address);

        $self->log(ERROR =>
                "Cannot convert \"$address\" into an address object"), return
            unless defined $mi;

        $address = $mi;
    }
    $self->{MMHL_address}  = $address          if defined $args->{address};

    $self->{MMHL_listname} = $args->{listname} if defined $args->{listname};
    $self->{MMHL_version}  = $args->{version}  if defined $args->{version};
    $self->{MMHL_software} = $args->{software} if defined $args->{software};
    $self->{MMHL_rfc}      = $args->{rfc}      if defined $args->{rfc};
    $self->{MMHL_type}     = $args->{type}     if defined $args->{type};

    $self->{MMHL_fns}      = [];
    $self;
}

#------------------------------------------

=method from HEAD|MESSAGE

Create a C<Mail::Message::Head::ListGroup> based in the specified MESSAGE
or message HEAD.

=cut

sub from($)
{  my ($class, $from) = @_;
   my $head = $from->isa('Mail::Message::Head') ? $from : $from->head;
   my $self = $class->new(head => $head);

   return () unless $self->findListFields;
   $self;
}

#------------------------------------------

=method clone

Make a copy of this object.  The collected fieldnames are copied and the
list type information.  No deep copy is made for the header: this is
only copied as reference.

=cut

sub clone()
{   my $self = shift;
    my $clone = bless %$self, ref $self;
    $clone->{MMHL_fns} = [ @{$self->{MMHL_fns}} ];
    $clone;
}

#------------------------------------------

=section The header

=method head

Returns the header object, which includes these fields.

=cut

sub head() { shift->{MMHL_head} }

#------------------------------------------

=method attach HEAD

Add a list group to a message HEAD.  The fields will be cloned(!)
into the header, so that the list group object can be used again.

=example attaching a list group to a message

 my $lg = Mail::Message::Head::ListGroup->new(...);
 $lg->attach($msg->head);
 $msg->head->addListGroup($lg);   # same

=example copying list information

 if(my $lg = $listmsg->head->listGroup)
 {   $msg->head->addListGroup($lg);
 }

=cut

sub attach($)
{   my ($self, $head) = @_;
    my $lg = ref($self)->clone;
    $self->{MMHL_head} = $head;

    $head->add($_->clone) for $self->fields;
    $lg;
}

#------------------------------------------

=method delete

Remove all the header lines which are combined in this list group
from the header.

=cut

sub delete()
{   my $self   = shift;
    my $head   = $self->head;
    $head->removeField($_) foreach $self->fields;
    $self;
}

#------------------------------------------

=section Access to the header

=method add (FIELD, VALUE) | OBJECT

Add a field to the header, using the list group.  When the list group
is already attached to a real message header, it will appear in that
one as well as being registed in this set.

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
    push @{$self->{MMHL_fns}}, $field->name;
    $self;
}

#------------------------------------------

=method fields

Return the fields which are defined for this list group.

=cut

sub fields()
{   my $self = shift;
    my $head = $self->head;
    map { $head->get($_) } @{$self->{MMHL_fns}};
}

#------------------------------------------

=method version 

Returns the version number of the software used by the mailing list
software.  This is ofthen not known, in which case C<undef> will be
returned.

=cut

sub version()
{  my $self = shift;
   $self->type;
   $self->{MMHL_version};
}

#------------------------------------------

=method software

Returns the name of the software as is defined in the headers.  The may
be slightly different from the return value of M<type()>, but usually
not too different.

=cut

sub software()
{  my $self = shift;
   $self->type;
   $self->{MMHL_software};
}

#------------------------------------------

=method rfc

When the mailing list software follows the guidelines of one of the dedictated
RFCs, then this will be returned otherwise C<undef>.  The return values can
be C<rfc2918>, C<rfc2369>, or C<undef>.

=cut

sub rfc()
{  my $self = shift;
   return $self->{MMHL_rfc} if defined $self->{MMHL_rfc};

   my $head = $self->head;
     defined $head->get('List-Post') ? 'rfc2369'
   : defined $head->get('List-Id')   ? 'rfc2918'
   :                                    undef;
}

#------------------------------------------

=method address

Returns a M<Mail::Message::Field::Address> object (or C<undef>) which
defines the posting address of the mailing list.

=cut

sub address()
{   my $self = shift;
    return $self->{MMHL_address} if exists $self->{MMHL_address};

    my $type = $self->type || 'Unknown';
    my $head = $self->head;

    my ($field, $address);
    if($type eq 'Smartlist' && defined($field = $head->get('X-Mailing-List')))
    {   $address = $1 if $field =~ m/\<([^>]+)\>/ }
    elsif($type eq 'YahooGroups')
    {   $address = $head->study('X-Apparently-To') }

    $address ||= $head->get('List-Post') || $head->get('Reply-To')
             || $head->get('Sender');
    $address = $address->study if ref $address;

       if(!defined $address) { ; }
    elsif(!ref $address)
    {   $address =~ s/\bowner-|-(?:owner|bounce|admin)\@//i;
        $address = Mail::Message::Field::Address->new(address => $address);
    }
    elsif($address->isa('Mail::Message::Field::Addresses'))
    {   # beautify
        $address     = ($address->addresses)[0];
        my $username = defined $address ? $address->username : '';
        if($username =~ s/^owner-|-(owner|bounce|admin)$//i)
        {   $address = Mail::Message::Field::Address->new
               (username => $username, domain => $address->domain);
        }
    }
    elsif($address->isa('Mail::Message::Field::URIs'))
    {   my $uri  = first { $_->scheme eq 'mailto' } $address->URIs;
        $address = defined $uri
                 ? Mail::Message::Field::Address->new(address => $uri->to)
                 : undef;
    }
    else  # Don't understand life anymore :-(
    {   undef $address;
    }

    $self->{MMHL_address} = $address;
}

#------------------------------------------

=method listname

Returns the name of the mailing list, which is usually a part of the
e-mail address which is used to post the messages to.

=cut

sub listname()
{   my $self = shift;
    return $self->{MMHL_listname} if exists $self->{MMHL_listname};

    my $head = $self->head;

    # Some lists have a field with the name only
    my $list = $head->get('List-ID') || $head->get('X-List')
            || $head->get('X-ML-Name');

    my $listname;
    if(defined $list)
    {   $listname = $list->study->decodedBody;
    }
    elsif(my $address = $self->address)
    {   $listname = $address->phrase || $address->address;
    }

    $self->{MMHL_listname} = $listname;
}

#------------------------------------------

=method type

Returns an abstract name for the list group; which mailing software is
controling it.  C<undef> is returned in case the type is not known, and
the other names are listed in L</Detected lists>.

=cut

sub type()
{   my $self = shift;
    return $self->{MMHL_type} if exists $self->{MMHL_type};

    my $head = $self->head;
    my ($type, $software, $version, $field);

    if(my $commpro = $head->get('X-ListServer'))  
    {   ($software, $version) = $commpro =~ m/^(.*)\s+LIST\s*([\d.]+)\s*$/;
        $type    = 'CommuniGate';
    }
    elsif(my $mailman = $head->get('X-Mailman-Version'))
    {   $version = "$mailman";
        $type    = 'Mailman';
    }
    elsif(my $majordomo = $head->get('X-Majordomo-Version'))
    {   $version = "$majordomo";
        $type    = 'Majordomo';
    }
    elsif(my $ecartis = $head->get('X-Ecartis-Version'))
    {   ($software, $version) = $ecartis =~ m/^(.*)\s+(v[\d.]+)/;
        $type    = 'Ecartis';
    }
    elsif(my $listar = $head->get('X-Listar-Version'))
    {   ($software, $version) = $listar =~ m/^(.*?)\s+(v[\w.]+)/;
        $type    = 'Listar';
    }
    elsif(defined($field = $head->get('List-Software'))
          && $field =~ m/listbox/i)
    {   ($software, $version) = $field =~ m/^(\S*)\s*(v[\d.]+)\s*$/;
        $type    = 'Listbox';
    }
    elsif(defined($field = $head->get('X-Mailing-List'))
          && $field =~ m[archive/latest])
    {   $type    = 'Smartlist' }
    elsif(defined($field = $head->get('Mailing-List')) && $field =~ m/yahoo/i )
    {   $type    = 'YahooGroups' }
    elsif(defined($field) && $field =~ m/(ezmlm)/i )
    {   $type    = 'Ezmlm' }
    elsif(my $fml = $head->get('X-MLServer'))
    {   ($software, $version) = $fml =~ m/^\s*(\S+)\s*\[\S*\s*([^\]]*?)\s*\]/;
        $type    = 'FML';
    }
    elsif(defined($field = $head->get('List-Subscribe')
                        || $head->get('List-Unsubscribe'))
          && $field =~ m/sympa/i)
    {   $type    = 'Sympa' }
    elsif(first { m/majordom/i } $head->get('Received'))
    {   # Majordomo is hard to recognize
        $type    = "Majordomo";
    }
    elsif($field = $head->get('List-ID') && $field =~ m/listbox\.com/i)
    {   $type    = "Listbox" }

    $self->{MMHL_version}  = $version  if defined $version;
    $self->{MMHL_software} = $software if defined $software;
    $self->{MMHL_type}     = $type;
}

#------------------------------------------

=method findListFields

Scan the header for fields which are usually contained in mailing list
software.  This method is automatically called when a list group is
constructed M<from()> an existing header or message.

Returned are the names of the list header fields found, in scalar
context the amount.  An empty list/zero indicates that this is not
a mailing list message.

Please warn the author of MailBox if you see that to few
or too many fields are included.

=cut

our $list_field_names
  = qr/ ^ (?: List|X-Envelope|X-Original ) - 
      | ^ (?: Precedence|Mailing-List ) $
      | ^ X-(?: Loop|BeenThere|Sequence|List|Sender|MLServer ) $
      | ^ X-(?: Mailman|Listar|Egroups|Encartis|ML ) -
      | ^ X-(?: Archive|Mailing|Original|Mail|ListServer ) -
      | ^ (?: Mail-Followup|Delivered|Errors|X-Apperently ) -To $
      /xi;

sub findListFields()
{   my $self = shift;
    my @names = map { $_->name } $self->head->grepNames($list_field_names);
    $self->{MMHL_fns} = \@names;
    @names;
}

#------------------------------------------

=section Error handling

=method print [FILEHANDLE]

Print the group to the specified FILEHANDLE or GLOB.  This is probably only
useful for debugging purposed.  The output defaults to the selected file
handle.

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || select;
    $self->print($out) foreach $self->fields;
}

#------------------------------------------

=method details

Produce information about the detected/create list group, which may be
helpful during debugging, by default to the selected file handle.

=cut

sub details()
{   my $self     = shift;
    my $type     = $self->type || 'Unknown';

    my $software = $self->software;
    undef $software if $type eq $software;
    my $version  = $self->version;
    my $release
      = defined $software
      ? (defined $version ? " ($software $version)" : " ($software)")
      : (defined $version ? " ($version)"           : '');

    my $address  = $self->address || 'unknown address';
    my $fields   = scalar $self->fields;
    "$type at $address$release, $fields fields";
}

#------------------------------------------

=chapter DETAILS

=section Mailing list fields

=subsection Detected lists

The M<Mail::Message::Head::ListGroup> class can detect many different
mailing lists, some of which are very popular and some of which are
rare.

Numerous fields in a header are addded when the message is passed
through a mailing list server.  Each list software has defined its own
fields, sometimes woth conflicting definitions.  There are also two
RFCs about mailing list: C<rfc2918> and C<rfc2369>.

The following lists are currently detected.  Between parenthesis is
the string returned by M<type()> when that differs from the software
name.

=over 4
=item * CommuniGate Pro (CommuniGate)
Commercial rfc2918 compliant implementation by Stalker Software Inc.
L<http://www.stalker.com>

=item * Ecartis
Commercial mailing list manager, formerly known as Listar. Produced
by NodeRunner Computing.  See L<http://www.ecartis.com>.

=item * Ezmlm
Open Source mailing list manager, available from L<http://www.ezmlm.org>.

=item * FML
Open Source mailing list manager, see L<http://www.fml.org>.

=item * Listar
Old name for Ecartis.

=item * Listbox
Mailing lists defined at L<http://listbox.com>.

=item * Mailman
GNU's mailing list manager, available from L<http://www.list.org>.

=item * Majordomo
Free (licenced) mailing list manager by Great Circle Associates,
available from L<http://www.greatcircle.com/majordomo/>

=item * Smartlist
Related to procmail, as expressed by their shared main page at
L<http://www.procmail.org/>.

=item * Yahoo! Groups (YahooGroups)
Mailing lists defined at L<http://groups.yahoo.com>.

=back

=cut

1;
