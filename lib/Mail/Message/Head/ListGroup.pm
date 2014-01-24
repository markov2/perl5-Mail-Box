
package Mail::Message::Head::ListGroup;
use base 'Mail::Message::Head::FieldGroup';

use strict;
use warnings;

use List::Util 'first';

=chapter NAME

Mail::Message::Head::ListGroup - mailinglist related header fields

=chapter SYNOPSIS

 my $lg = Mail::Message::Head::ListGroup->new(head => $head, ...);
 $head->addListGroup($lg);

 my $lg = $head->addListGroup(...);

 $lg->delete;

=chapter DESCRIPTION

A I<list group> is a set of header fields which are added by mailing-list
managing software.  This class knowns various details about that software.

The knowledge and test messages which are used to initially implement
this module is taken from M<Mail::ListDetector>, written by
Michael Stevens <mailto:michael@etla.org>.  The logic is redesigned to
add flexibility and use the powerful MailBox features.

=chapter METHODS

=section Constructors

=c_method new $fields, %options

Construct an object which maintains one set of mailing list headers

=option  rfc 'rfc2919'|'rfc2369'
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

=error Cannot convert "$string" into an address object
The M<new(address)> is coerced into a M<Mail::Message::Field::Address>,
which fails.  Have a look at M<Mail::Message::Field::Address::coerce()>
to see what valid arguments are.

=cut

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

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
    $self->{MMHL_rfc}      = $args->{rfc}      if defined $args->{rfc};
    $self->{MMHL_fns}      = [];
    $self;
}

#------------------------------------------

=method from $head|$message

Create a C<Mail::Message::Head::ListGroup> based in the specified $message
or message $head.

=cut

sub from($)
{   my ($class, $from) = @_;
    my $head = $from->isa('Mail::Message::Head') ? $from : $from->head;
    my $self = $class->new(head => $head);

    return () unless $self->collectFields;

    my ($type, $software, $version, $field);
    if(my $communigate = $head->get('X-ListServer'))
    {   ($software, $version) = $communigate =~ m/^(.*)\s+LIST\s*([\d.]+)\s*$/i;
        $type    = ($software =~ m/Pro/ ? 'CommuniGatePro' : 'CommuniGate');
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
    elsif($field = first { m!LISTSERV-TCP/IP!s } $head->get('Received'))
    {   # Listserv is hard to recognise
        ($software, $version) = $field =~
            m!\( (LISTSERV-TCP/IP) \s+ release \s+ (\S+) \)!xs;
        $type = 'Listserv';
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

    $self->detected($type, $software, $version);
    $self;
}

#------------------------------------------

=method rfc

When the mailing list software follows the guidelines of one of the dedicated
RFCs, then this will be returned otherwise C<undef>.  The return values can
be C<rfc2919>, C<rfc2369>, or C<undef>.

=cut

sub rfc()
{  my $self = shift;
   return $self->{MMHL_rfc} if defined $self->{MMHL_rfc};

   my $head = $self->head;
     defined $head->get('List-Post') ? 'rfc2369'
   : defined $head->get('List-Id')   ? 'rfc2919'
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
    {   $address = $head->get('X-Apparently-To')->unfoldedBody }
    elsif($type eq 'Listserv')
    {   $address = $head->get('Sender') }

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

=section Access to the header

=ci_method isListGroupFieldName $name
=cut

my $list_field_names
  = qr/ ^ (?: List|X-Envelope|X-Original ) - 
      | ^ (?: Precedence|Mailing-List|Approved-By ) $
      | ^ X-(?: Loop|BeenThere|Sequence|List|Sender|MLServer ) $
      | ^ X-(?: Mailman|Listar|Egroups|Encartis|ML ) -
      | ^ X-(?: Archive|Mailing|Original|Mail|ListServer ) -
      | ^ (?: Mail-Followup|Delivered|Errors|X-Apperently ) -To $
      /xi;

sub isListGroupFieldName($) { $_[1] =~ $list_field_names }

#------------------------------------------

=section Internals

=method collectFields

Scan the header for fields which are usually contained in mailing list
software.  This method is automatically called when a list group is
constructed M<from()> an existing header or message.

Returned are the names of the list header fields found, in scalar
context the amount.  An empty list/zero indicates that this is not
a mailing list message.

Please warn the author of MailBox if you see that to few
or too many fields are included.

=cut

sub collectFields()
{   my $self = shift;
    my @names = map { $_->name } $self->head->grepNames($list_field_names);
    $self->addFields(@names);
    @names;
}

#------------------------------------------

=section Error handling

=method details

Produce information about the detected/create list group, which may be
helpful during debugging, by default to the selected file handle.

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
RFCs about mailing list: C<rfc2919> and C<rfc2369>.

The following lists are currently detected.  Between parenthesis is
the string returned by M<type()> when that differs from the software
name.

=over 4
=item * CommuniGate

Legacy commercial MacOS implementation by Stalker Software Inc.
L<http://www.stalker.com/mac/default.html>

=item * CommuniGate Pro (CommuniGatePro)
Commercial rfc2919 compliant implementation by Stalker Software Inc.
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

=item * Listserv
Commercial mailing list manager, produced by L-Soft. See
L<http://www.lsoft.com/>.

=back

=cut

1;
