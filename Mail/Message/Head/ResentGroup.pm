
use strict;

package Mail::Message::Head::ResentGroup;
use base 'Mail::Reporter';

use Scalar::Util 'weaken';
use Mail::Message::Field::Fast;

use Sys::Hostname;

=head1 NAME

Mail::Message::Head::ResentGroup - a group of header fields about resending

=head1 SYNOPSIS

 my $rg = Mail::Message::Head::ResentGroup->new(head => $head,
              From => 'me@home.nl', To => 'You@tux.aq');
 $head->addResentGroup($rg);

 my $rg = $head->addResentGroup(From => 'me');

 my @from = $rg->From;

 my @rgs = $head->resentGroups;
 $rg[2]->delete if @rgs > 2;

=head1 DESCRIPTION

A I<resent group> is a set of header lines which describe a intermediate
step in the message transport.  Resent groups B<have NOTHING to do> with
user activety; there is no relation to the user's sense of creating
C<reply>, C<forward> or C<bounce> messages at all!

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

my @ordered_field_names = qw/return_path delivered_to received date from
  sender to cc bcc message_id/;

#------------------------------------------

=method new [FIELDS], OPTIONS

Create an object which maintains one set of resent headers.  The
FIELDS are Mail::Message::Field objects from the same header.

OPTIONS which start with capitals will be used to construct additional
fields.  These option names are prepended with C<Resent->, keeping the
capitization of what is specified.

=option  head OBJECT
=default head <required>

The header where this resent group belongs to.

=option  Received STRING
=default Received <required>

The C<Received> field is the starting line for a resent group of header
lines, therefore it is obligatory.

=option  Date STRING
=default Date <now>

When this resent-group is dispatched by the resender of the message. Like
the C<Date> field, it is not the date and time that the message was
actually transported.

=option  From STRING|OBJECT|OBJECTS
=default From <required>

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

    $self->set($_)                     # add specified object fields
        foreach @{$args->{fields}};

    $self->set($_, $args->{$_})        # add key-value paired fields
        foreach grep m/^[A-Z]/, keys %$args;

    my $head = $self->{MMHR_head} = $args->{head};
    $self->log(INTERNAL => "Message header required for ResentGroup")
       unless defined $head;

    weaken( $self->{MMHR_head} );

    $self->createReceived unless defined $self->{MMHR_received};
    $self;
}

#------------------------------------------

=head2 The Header

=cut

#------------------------------------------

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

=head2 Access to the Header

=cut

#------------------------------------------

=method set (FIELD =E<gt> VALUE) | OBJECT

Set a FIELD to a (new) VALUE.  The FIELD names which do not start with
'Resent-*' but need it will have that added.  It is also an option to
specify a fully prepared message field OBJECT.  In any case, a field
OBJECT is returned.
See also Mail::Message::Head::resent() and
Mail::Message::Construct::bounce().

=examples

 my @rgs  = $msg->head->resentGroups;
 my $this = $rgs[0];
 $this->set(To => 'fish@tux.aq');
 $msg->send;

 $msg->head->resent(To => 'fish@tux.aq');   # the same
 $msg->send;

 $msg->bounce(To => 'fish@tux.aq')->send;   # the same

=cut

sub set($$)
{   my $self  = shift;

    my ($field, $name, $value);
    if(@_==1) { $field = shift }
    else
    {   my ($fn, $value) = @_;
        $name  = $fn =~ m!^(received|return\-path|delivered\-to|resent\-\w*)$!i ? $fn
               : "Resent-$fn";

        $field = Mail::Message::Field::Fast->new($name, $value);
    }

    $name = $field->name;
    $name =~ s/^resent\-//;
    $name =~ s/\-/_/g;
    $self->{ "MMHR_$name" } = $field;
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
returned as Mail::Address objects.

=cut

sub from()
{   my $from = shift->{MMHR_from} or return ();
    wantarray ? $from->addresses : $from;
}

#------------------------------------------

=method sender

In scalar context, the C<Resent-Sender> field is returned.  In list
context, the addresses as specified within the from field are
returned as Mail::Address objects.

=cut

sub sender()
{   my $sender = shift->{MMHR_sender} or return ();
    wantarray ? $sender->addresses : $sender;
}

#------------------------------------------

=method to

In scalar context, the C<Resent-To> field is returned.  In list context,
the addresses as specified within the to field are returned as
Mail::Address objects.

=cut

sub to()
{   my $to = shift->{MMHR_to} or return ();
    wantarray ? $to->addresses : $to;
}

#------------------------------------------

=method cc

In scalar context, the C<Resent-Cc> field is returned.  In list context,
the addresses as specified within the cc field are returned as
Mail::Address objects.

=cut

sub cc()
{   my $cc = shift->{MMHR_cc} or return ();
    wantarray ? $cc->addresses : $cc;
}

#------------------------------------------

=method bcc

In scalar context, the C<Resent-Bcc> field is returned.  In list context,
the addresses as specified within the bcc field are returned as
Mail::Address objects.  Bcc fields are not transmitted (hidden for
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

=head2 Reading and Writing [internals]

=cut

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

#-------------------------------------------

=method createReceived

Create a recieved field for this resent group.  This is automatically
called if none was specified during creation of this resent group object.

The content of this field is described in RFC2821 section 4.4.  It could use
some improvement.

=cut

my $unique_received_id = 'rc'.time;

sub createReceived()
{   my $self   = shift;
    my $head   = $self->{MMHR_head};
    my $sender = $head->message->sender;

    my $received
      = 'from ' . $sender->format
      . ' by '  . hostname
      . ' with SMTP'
      . ' id '  . $unique_received_id++
      . ' for ' . $head->get('To')  # may be wrong
      . '; '. Mail::Message::Field->toDate;

    $self->set(Received => $received);
}

#-------------------------------------------

1;
