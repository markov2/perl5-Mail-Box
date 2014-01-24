
use strict;

package Mail::Message::Head::ResentGroup;
use base 'Mail::Message::Head::FieldGroup';

use Scalar::Util 'weaken';
use Mail::Message::Field::Fast;

use Sys::Hostname 'hostname';
use Mail::Address;

=chapter NAME

Mail::Message::Head::ResentGroup - header fields tracking message delivery

=chapter SYNOPSIS

 my $rg = Mail::Message::Head::ResentGroup->new(head => $head,
              From => 'me@home.nl', To => 'You@tux.aq');
 $head->addResentGroup($rg);

 my $rg = $head->addResentGroup(From => 'me');

 my @from = $rg->From;

 my @rgs = $head->resentGroups;
 $rg[2]->delete if @rgs > 2;

=chapter DESCRIPTION

A I<resent group> is a set of header fields which describe one intermediate
step in the message transport.  Resent groups B<have NOTHING to do> with
user activety; there is no relation to the C<user's> sense of creating
reply, forward, or bounce messages at all!

=chapter METHODS

=c_method new [$fields], %options

Create an object which maintains one set of resent headers.  The
$fields are M<Mail::Message::Field> objects from the same header.

%options which start with capitals will be used to construct additional
fields.  These option names are prepended with C<Resent-*>, keeping the
capitization of what is specified.

=option  head OBJECT
=default head <created automatically>
The header where the data is stored in. By default a
M<Mail::Message::Head::Partial> is created for you.

=option  message_head HEAD
=default message_head C<undef>
The real header of the message where this resent group is part of.  The
C<head> used in this class is only a container for a subset of fields.

=option  Received STRING
=default Received <created>
The C<Received> field is the starting line for a resent group of header
lines. If it is not defined, one is created using M<createReceived()>.

=option  Date STRING
=default Date <now>

When this resent-group is dispatched by the resender of the message. Like
the C<Date> field, it is not the date and time that the message was
actually transported.

=requires From STRING|OBJECT|OBJECTS

=option  Sender STRING|OBJECT
=default Sender undef

Only permitted when more than one from address is specified.  In this case,
it selects one of these addresses as the main originator of the message.

=option  To STRING|OBJECT|OBJECTS
=default To undef

=option  Cc STRING|OBJECT|OBJECTS
=default Cc undef

=option  Bcc STRING|OBJECT|OBJECTS
=default Bcc undef

=option  Message-ID STRING|FIELD
=default Message-ID <uniquely created>

The C<Resent-Message-ID> which identifies this resent group.  The FIELD
must contain a message id.

=option  Return-Path STRING|FIELD
=default Return-Path undef

=option  Delivered-To STRING|FIELD
=default Delivered-To undef

=error Message header required for creation of ResentGroup.

It is required to know to which header the resent-group
is created.  Use the C<head> option.  Maybe you should use
M<Mail::Message::Head::Complete::addResentGroup()> with DATA, which will
organize the correct initiations for you.

=cut

# all lower cased!
my @ordered_field_names =
  ( 'return-path', 'delivered-to' , 'received', 'resent-date'
  , 'resent-from', 'resent-sender', , 'resent-to', 'resent-cc'
  , 'resent-bcc', 'resent-message-id'
  );

my %resent_field_names = map { ($_ => 1) } @ordered_field_names;

sub init($$)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMHR_real}  = $args->{message_head};

    $self->set(Received => $self->createReceived)
        if $self->orderedFields && ! $self->received;

    $self;
}

=method from [<$head|$message>, %options]
WARNING: this method has two very different purposes.  For backward
compatibility reasons, without arguments M<resentFrom()> is called to
return the C<From> field of this resent group.

With any arguments, a list of C<Mail::Message::Head::ResentGroup> objects
is returned, taken from the specified $message or message $head.

=cut

sub from($@)
{   return $_[0]->resentFrom if @_ == 1;   # backwards compat

    my ($class, $from, %args) = @_;
    my $head = $from->isa('Mail::Message::Head') ? $from : $from->head;

    my (@groups, $group, $return_path, $delivered_to);

    foreach my $field ($head->orderedFields)
    {   my $name = $field->name;
        next unless $resent_field_names{$name};

        if($name eq 'return-path')              { $return_path  = $field }
        elsif($name eq 'delivered-to')          { $delivered_to = $field }
        elsif(substr($name, 0, 7) eq 'resent-')
        {   $group->add($field) if defined $group }
        elsif($name eq 'received')
        {
            $group = Mail::Message::Head::ResentGroup
                          ->new($field, message_head => $head);
            push @groups, $group;

            $group->add($delivered_to) if defined $delivered_to;
            undef $delivered_to;

            $group->add($return_path) if defined $return_path;
            undef $return_path;
        }
    }

    @groups;
}

#------------------------------------------

=section The header

=method messageHead [$head]
Returns (optionally after setting) the real header where this resent group
belongs to.  This may be undef at creation, and then later filled in
when M<Mail::Message::Head::Complete::addResentGroup()> is called.

=cut

sub messageHead(;$)
{   my $self = shift;
    @_ ? $self->{MMHR_real} = shift : $self->{MMHR_real};
}

=method orderedFields
Returns the fields in the order as should appear in header according
to rfc2822.  For the C<Resent-*> fields of the group, the order is
not that important, but the C<Return-Path>, C<Delivered-To>, and C<Received>
must come first.  Only fields mentioned in the RFC are returned.
=cut

sub orderedFields()
{   my $head = shift->head;
    map { $head->get($_) || () } @ordered_field_names;
}

=method set <$field, $value> | $object
Set a $field to a (new) $value.  The $field names which do not start with
'Resent-*' but need it will have that added.  It is also an option to
specify a fully prepared message field $object.  In any case, a field
$object is returned.

=examples

 my $this = Mail::Message::Head::ResentGroup->new;
 $this->set(To => 'fish@tux.aq');
 $msg->addResentGroup($this);
 $msg->send;

 $msg->bounce(To => 'fish@tux.aq')->send;   # the same

 my $this = Mail::Message::Head::ResentGroup
     ->new(To => 'fish@tux.aq');

=cut

sub set($;$)
{   my $self  = shift;
    my $field;

    if(@_==1) { $field = shift }
    else
    {   my ($fn, $value) = @_;
        my $name  = $resent_field_names{lc $fn} ? $fn : "Resent-$fn";
        $field = Mail::Message::Field::Fast->new($name, $value);
    }

    $self->head->set($field);
    $field;
}

sub fields()     { shift->orderedFields }
sub fieldNames() { map { $_->Name } shift->orderedFields }

sub delete()
{   my $self   = shift;
    my $head   = $self->messageHead;
    $head->removeField($_) foreach $self->fields;
    $self;
}

=method add <$field, $value> | $object
All fields appear only once, so C<add()> behaves as M<set()>.
=cut

sub add(@) { shift->set(@_) }

=method addFields [$fieldnames]
Not applicable to resent-groups: the same name can appear in more than
one group.  Therefore, a FIELDNAME is sufficiently distinctive.

=cut

sub addFields(@) { shift->notImplemented }

#-------------------------------------------

=section Access to the header

=method returnPath
The field which describes the C<Return-Path> of this resent group.
=cut

sub returnPath() { shift->{MMHR_return_path} }

=method deliveredTo
The field which describes the C<Delivered-To> of this resent group.
=cut

sub deliveredTo() { shift->head->get('Delivered-To') }

=method received
The field which describes the C<Received> data of this resent group.
=cut

sub received() { shift->head->get('Received') }

=method receivedTimestamp
The timestamp as stored within the C<Received> field converted to
local system time.

=cut

sub receivedTimestamp()
{   my $received = shift->received or return;
    my $comment  = $received->comment or return;
    Mail::Message::Field->dateToTimestamp($comment);
}

=method date
Returns the C<Resent-Date> field, or C<undef> if it was not defined.
=cut

sub date($) { shift->head->get('resent-date') }

=method dateTimestamp
The timestamp as stored within the C<Resent-Date> field converted to
local system time.
=cut

sub dateTimestamp()
{   my $date = shift->date or return;
    Mail::Message::Field->dateToTimestamp($date->unfoldedBody);
}

=method resentFrom
In scalar context, the C<Resent-From> field is returned.  In list
context, the addresses as specified within the from field are
returned as M<Mail::Address> objects.

For reasons of backward compatibility and consistency, the M<from()>
method will return the same as this method.
=cut

sub resentFrom()
{   my $from = shift->head->get('resent-from') or return ();
    wantarray ? $from->addresses : $from;
}

=method sender
In scalar context, the C<Resent-Sender> field is returned.  In list
context, the addresses as specified within the from field are
returned as M<Mail::Address> objects.
=cut

sub sender()
{   my $sender = shift->head->get('resent-sender') or return ();
    wantarray ? $sender->addresses : $sender;
}

=method to
In scalar context, the C<Resent-To> field is returned.  In list context,
the addresses as specified within the to field are returned as
M<Mail::Address> objects.
=cut

sub to()
{   my $to = shift->head->get('resent-to') or return ();
    wantarray ? $to->addresses : $to;
}

=method cc
In scalar context, the C<Resent-Cc> field is returned.  In list context,
the addresses as specified within the cc field are returned as
M<Mail::Address> objects.
=cut

sub cc()
{   my $cc = shift->head->get('resent-cc') or return ();
    wantarray ? $cc->addresses : $cc;
}

=method bcc
In scalar context, the C<Resent-Bcc> field is returned.  In list context,
the addresses as specified within the bcc field are returned as
M<Mail::Address> objects.  Bcc fields are not transmitted (hidden for
external parties).
=cut

sub bcc()
{   my $bcc = shift->head->get('resent-bcc') or return ();
    wantarray ? $bcc->addresses : $bcc;
}

=method destinations
Returns a list of all addresses specified in the C<Resent-To>, C<-Cc>, and
C<-Bcc> fields of this resent group.
=cut

sub destinations()
{   my $self = shift;
    ($self->to, $self->cc, $self->bcc);
}

=method messageId
Returns the message-ID used for this group of resent lines.
=cut

sub messageId() { shift->head->get('resent-message-id') }

=ci_method isResentGroupFieldName $name
=cut

sub isResentGroupFieldName($) { $resent_field_names{lc $_[1]} }

#------------------------------------------

=section Internals

=method createReceived [$domain]

Create a received field for this resent group.  This is automatically
called if none was specified during creation of this resent group object.

The content of this field is described in RFC2821 section 4.4.  It could use
some improvement.

=cut

my $unique_received_id = 'rc'.time;

sub createReceived(;$)
{   my ($self, $domain) = @_;

    unless(defined $domain)
    {   my $sender = ($self->sender)[0] || ($self->resentFrom)[0];
        $domain    = $sender->host if defined $sender;
    }

    my $received
      = 'from ' . $domain
      . ' by '  . hostname
      . ' with SMTP'
      . ' id '  . $unique_received_id++
      . ' for ' . $self->head->get('Resent-To')  # may be wrong
      . '; '. Mail::Message::Field->toDate;

    $received;
}

#-------------------------------------------

=section Error handling

=cut

1;
