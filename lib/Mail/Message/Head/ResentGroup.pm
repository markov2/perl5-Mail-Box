
use strict;

package Mail::Message::Head::ResentGroup;
use base 'Mail::Reporter';

use Scalar::Util 'weaken';
use Mail::Message::Field::Fast;

use Sys::Hostname;

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

=c_method new [FIELDS], OPTIONS

Create an object which maintains one set of resent headers.  The
FIELDS are M<Mail::Message::Field> objects from the same header.

OPTIONS which start with capitals will be used to construct additional
fields.  These option names are prepended with C<Resent->, keeping the
capitization of what is specified.

=requires head OBJECT

The header where this resent group belongs to.

=requires Received STRING

The C<Received> field is the starting line for a resent group of header
lines, therefore it is obligatory.

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

my @ordered_field_names = qw/return_path delivered_to received date from
  sender to cc bcc message_id/;

sub new(@)
{   my $class = shift;

    my @fields;
    push @fields, shift while ref $_[0];

    $class->SUPER::new(@_, fields => \@fields);
}

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->set($_)                     # add specified object fields
        foreach @{$args->{fields}};

    $self->set($_, $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    my $head = $self->{MMHR_head} = $args->{head};
    $self->log(ERROR => "Message header required for creation of ResentGroup.")
       unless defined $head;

    weaken( $self->{MMHR_head} );

    $self->createReceived unless defined $self->{MMHR_received};
    $self;
}

#------------------------------------------

=section The header

=method delete

Remove all the header lines which are combined in this resent group
from the header.

=cut

sub delete()
{   my $self   = shift;
    my $head   = $self->{MMHR_head};
    my @fields = grep {ref $_ && $_->isa('Mail::Message::Field')}
                     values %$self;

    $head->removeField($_) foreach @fields;
    $self;
}

#------------------------------------------

=method orderedFields

Returns the fields in the order as should appear in header according
to rfc2822.  For the C<Resent-> fields of the group, the order is
not that important, but the C<Return-Path>, C<Delivered-To>, and C<Received>
must come first.  Only fields mentioned in the RFC are returned.

=cut

sub orderedFields()
{   my $self   = shift;
    map { $self->{ "MMHR_$_" } || () } @ordered_field_names;
}

#-------------------------------------------

=method print [FILEHANDLE]

=cut

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $_->print($fh) foreach $self->orderedFields;
}

#------------------------------------------

=section Access to the header

=method set (FIELD =E<gt> VALUE) | OBJECT

Set a FIELD to a (new) VALUE.  The FIELD names which do not start with
'Resent-*' but need it will have that added.  It is also an option to
specify a fully prepared message field OBJECT.  In any case, a field
OBJECT is returned.

=examples

 my $this = Mail::Message::Head::ResentGroup->new;
 $this->set(To => 'fish@tux.aq');
 $msg->addResentGroup($this);
 $msg->send;

 $msg->bounce(To => 'fish@tux.aq')->send;   # the same

=cut

our $resent_field_names
   = qr/^(?:received$|return\-path$|delivered\-to$|resent\-)/i;

sub set($$)
{   my $self  = shift;

    my ($field, $name, $value);
    if(@_==1) { $field = shift }
    else
    {   my ($fn, $value) = @_;
        $name  = $fn =~ $resent_field_names ? $fn : "Resent-$fn";
        $field = Mail::Message::Field::Fast->new($name, $value);
    }

    $name = $field->name;
    $name =~ s/^resent\-//;
    $name =~ s/\-/_/g;

    $self->{ "MMHR_$name" } = $field;
    $field;
}

#------------------------------------------

=method returnPath

The field which describes the C<Return-Path> of this resent group.

=cut

sub returnPath() { shift->{MMHR_return_path} }

#------------------------------------------

=method deliveredTo

The field which describes the C<Delivered-To> of this resent group.

=cut

sub deliveredTo() { shift->{MMHR_delivered_to} }

#------------------------------------------

=method received

The field which describes the C<Received> data of this resent group.

=cut

sub received() { shift->{MMHR_received} }

#------------------------------------------

=method receivedTimestamp

The timestamp as stored within the C<Received> field converted to
local system time.

=cut

sub receivedTimestamp()
{   my $received = shift->{MMHR_received} or return;
    my $comment  = $received->comment or return;
    Mail::Message::Field->dateToTimestamp($comment);
}

#------------------------------------------

=method date

Returns the C<Resent-Date> field, or C<undef> if it was not defined.

=cut

sub date($) { shift->{MMHR_date} }

#------------------------------------------

=method dateTimestamp

The timestamp as stored within the C<Resent-Date> field converted to
local system time.

=cut

sub dateTimestamp()
{   my $date = shift->{MMHR_date} or return;
    Mail::Message::Field->dateToTimestamp($date);
}

#------------------------------------------

=method from

In scalar context, the C<Resent-From> field is returned.  In list
context, the addresses as specified within the from field are
returned as M<Mail::Address> objects.

=cut

sub from()
{   my $from = shift->{MMHR_from} or return ();
    wantarray ? $from->addresses : $from;
}

#------------------------------------------

=method sender

In scalar context, the C<Resent-Sender> field is returned.  In list
context, the addresses as specified within the from field are
returned as M<Mail::Address> objects.

=cut

sub sender()
{   my $sender = shift->{MMHR_sender} or return ();
    wantarray ? $sender->addresses : $sender;
}

#------------------------------------------

=method to

In scalar context, the C<Resent-To> field is returned.  In list context,
the addresses as specified within the to field are returned as
M<Mail::Address> objects.

=cut

sub to()
{   my $to = shift->{MMHR_to} or return ();
    wantarray ? $to->addresses : $to;
}

#------------------------------------------

=method cc

In scalar context, the C<Resent-Cc> field is returned.  In list context,
the addresses as specified within the cc field are returned as
M<Mail::Address> objects.

=cut

sub cc()
{   my $cc = shift->{MMHR_cc} or return ();
    wantarray ? $cc->addresses : $cc;
}

#------------------------------------------

=method bcc

In scalar context, the C<Resent-Bcc> field is returned.  In list context,
the addresses as specified within the bcc field are returned as
M<Mail::Address> objects.  Bcc fields are not transmitted (hidden for
external parties).

=cut

sub bcc()
{   my $bcc = shift->{MMHR_bcc} or return ();
    wantarray ? $bcc->addresses : $bcc;
}

#------------------------------------------

=method destinations

Returns a list of all addresses specified in the C<Resent-To>, C<-Cc>, and
C<-Bcc> fields of this resent group.

=cut

sub destinations()
{   my $self = shift;
    ($self->to, $self->cc, $self->bcc);
}

#------------------------------------------

=method messageId

Returns the message-ID used for this group of resent lines.

=cut

sub messageId() { shift->{MMHR_message_id} }

#------------------------------------------

=section Internals

=method createReceived [DOMAIN]

Create a recieved field for this resent group.  This is automatically
called if none was specified during creation of this resent group object.

The content of this field is described in RFC2821 section 4.4.  It could use
some improvement.

=cut

my $unique_received_id = 'rc'.time;

sub createReceived(;$)
{   my ($self, $domain) = @_;
    my $head   = $self->{MMHR_head};

    unless(defined $domain)
    {   my $sender = ($self->sender)[0] || ($self->from)[0];
        $domain    = $sender->domain if defined $sender;
    }

    my $received
      = 'from ' . $domain
      . ' by '  . hostname
      . ' with SMTP'
      . ' id '  . $unique_received_id++
      . ' for ' . $head->get('To')  # may be wrong
      . '; '. Mail::Message::Field->toDate;

    $self->set(Received => $received);
}

#-------------------------------------------

=section Error handling

=cut

1;
