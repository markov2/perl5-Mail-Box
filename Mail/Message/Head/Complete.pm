use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Scalar::Util 'weaken';
use List::Util 'sum';

=chapter NAME

Mail::Message::Head::Complete - the header of one message

=chapter SYNOPSIS

 my $head = Mail::Message::Head::Complete->new;
 See Mail::Message::Head

=chapter DESCRIPTION

E-mail's message can be in various states: unread, partially read, and
fully read.  The class stores a message of which all header lines are
known for sure.

=chapter METHODS

=section Constructors

=method clone [FIELDS]

Make a copy of the header, optionally limited only to the header lines
specified by FIELDS.  The lines which are taken must start with one of the
list.  If no list is specified, all will be taken.

=example

 my $newhead = $head->clone('Subject', 'Received');

=cut

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new($self->logSettings);

    $copy->addNoRealize($_->clone) foreach $self->orderedFields;
    $copy->modified(1);
    $copy;
}

#------------------------------------------

sub build(@)
{   my $self = shift;
    my $head = $self->new;
    $head->add(shift, shift) while @_;
    $head;
}

#------------------------------------------

=section The header

=cut

sub isDelayed() {0}

#------------------------------------------

=method nrLines

Return the number of lines needed to display this header (including
the trailing newline)

=cut

sub nrLines() { sum 1, map { $_->nrLines } shift->orderedFields }

#------------------------------------------

=method size

Return the number of bytes needed to display this header (including
the trailing newline).  On systems which use CRLF as line separator,
the number of lines in the header (see M<nrLines()>) must be added to
find the actual size in the file.

=cut

sub size() { sum 1, map {$_->size} shift->orderedFields }

#------------------------------------------

=section Access to the header

=method add FIELD | LINE | (NAME,BODY[,ATTRS])

Add a field to the header.  If a field is added more than once, all values
are stored in the header, in the order they are added.

When a FIELD object is specified (some M<Mail::Message::Field> instance), that
will be added.  Another possibility is to specify a raw header LINE, or a
header line nicely split-up in NAME and BODY, in which case the
field constructor is called for you.

LINE or BODY specifications which are terminated by a new-line are considered 
to be correctly folded.  Lines which are not terminated by a new-line will
be folded when needed: new-lines will be added where required.  It is strongly
adviced to let Mail::Box do the folding for you.

The return value of this method is the M<Mail::Message::Field> object
which is created (or was specified).

=examples

 my $head  = M<Mail::Message::Head>->new;
 $head->add('Subject: hi!');
 $head->add(From => 'me@home');
 my $field = M<Mail::Message::Field>->new('To: you@there');
 $head->add($field);
 my Mail::Message::Field $s = $head->add(Sender => 'I');

=cut

sub add(@)
{   my $self = shift;

    # Create object for this field.

    my $field
      = @_==1 && ref $_[0] ? shift     # A fully qualified field is added.
      : ($self->{MMH_field_type} || 'Mail::Message::Field::Fast')->new(@_);

    $field->setWrapLength;

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    $self->addOrderedFields($field);

    if(defined $known->{$name})
    {   if(ref $known->{$name} eq 'ARRAY') { push @{$known->{$name}}, $field }
        else { $known->{$name} = [ $known->{$name}, $field ] }
    }
    else
    {   $known->{$name} = $field;
    }

    $self->{MMH_modified}++;
    $field;
}

#------------------------------------------

=method count NAME

Count the number of fields with this NAME.  Most fields will return 1:
only one occurance in the header.  As example, the C<Received> fields
are usually present more than once.

=cut

sub count($)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};

      ! defined $value ? 0
    : ref $value       ? @$value
    :                    1;
}

#------------------------------------------

=method names

Returns a full ordered list of known field names, as defined in the
header.  Fields which were reset() to be empty will still be
listed here.

=cut

sub names() {shift->knownNames}
 
#------------------------------------------

=method grepNames [NAMES|ARRAY-OF-NAMES|REGEXS]

Filter from all header names the names which start will any of the
specified list.  When no names are specified, all names will be returned.
The list is ordered as they where read from file, or added later.

The NAMES are regular expressions, and will all be matched case insensitive
and attached to the front of the string only.  You may also specify
one or more prepared regexes.

=examples

 print $head->grepNames();         # same as $head->names
 print $head->grepNames('X-', 'Subject', ');
 print $head->grepNames('To\b');   # will only select To

=cut

sub grepNames(@)
{   my $self = shift;
    my @take;
    push @take, (ref $_ eq 'ARRAY' ? @$_ : $_) foreach @_;

    return $self->names unless @take;

    my $take;
    if(@take==1 && ref $take[0] eq 'Regexp')
    {   $take    = $take[0];   # one regexp prepared already
    }
    else
    {   # I love this trick:
        local $" = ')|(?:';
        $take    = qr/^(?:(?:@take))/i;
    }

    grep {$_->Name =~ $take} $self->orderedFields;
}

#------------------------------------------

=method set FIELD | LINE | (NAME, BODY [,ATTRS])

The C<set> method is similar to the M<add()> method, and takes the same
options. However, existing values for fields will be removed before a new
value is added.

=cut

my @skip_none = qw/content-transfer-encoding content-disposition/;
my %skip_none = map { ($_ => 1) } @skip_none;

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';
    $self->{MMH_modified}++;

    # Create object for this field.
    my $field = @_==1 && ref $_[0] ? shift->clone : $type->new(@_);

    my $name  = $field->name;         # is already lower-cased
    my $known = $self->{MMH_fields};

    # Internally, non-existing content-info are in the body stored as 'none'
    # The header will not contain these lines.

    if($skip_none{$name} && $field->body eq 'none')
    {   delete $known->{$name};
        return $field;
    }

    $field->setWrapLength;
    $known->{$name} = $field;

    $self->addOrderedFields($field);
    $field;
}

#------------------------------------------

=method reset NAME, FIELDS

Replace the values in the header fields named by NAME with the values
specified in the list of FIELDS. A single name can correspond to multiple
repeated fields.

For C<Received> fields, you should take a look at I<resent groups>, as
implemented in M<Mail::Message::Head::ResentGroup>.  Removing those
lines without their related lines is not a smart idea.  Read the
details M<Mail::Message::Head::ResentGroup::delete()>.

If FIELDS is empty, the corresponding NAME fields will
be removed. The location of removed fields in the header order will be
remembered. Fields with the same name which are added later will appear at
the remembered position.  This is equivalent to the M<delete()> method.

=examples

 # reduce number of 'Keywords' lines to last 5)
 my @keywords = $head->get('Keywords');
 $head->reset('Keywords', @keywords[-5..-1]) if @keywords > 5;

 # Reduce the number of Received lines to only the last added one.
 my @rgs = $head->resentGroups;
 shift @rgs;     # keep this one (later is added in front)
 $_->delete foreach @rgs;

=cut

sub reset($@)
{   my ($self, $name) = (shift, lc shift);

    my $known = $self->{MMH_fields};

    if(@_==0)
    {   $self->{MMH_modified}++ if delete $known->{$name};
        return ();
    }

    $self->{MMH_modified}++;

    # Cloning required, otherwise double registrations will not be
    # removed from the ordered list: that's controled by 'weaken'

    my @fields = map {$_->clone} @_;

    if(@_==1) { $known->{$name} = $fields[0] }
    else      { $known->{$name} = [@fields]  }

    $self->addOrderedFields(@fields);
    $self;
}
 
#------------------------------------------

=method delete NAME

Remove the field with the specified name.  If the header contained
multiple lines with the same name, they will be replaced all together.
This method simply calls M<reset()> without replacement fields.

=cut

sub delete($) { $_[0]->reset($_[1]) }

#------------------------------------------

=method removeField FIELD

Remove the specified FIELD from the header.  This is useful when there
are possible more than one fields with the same name, and you need to
remove exactly one of them.  Also have a look at M<delete()>, M<reset()>,
and M<set()>.

=warning Cannot remove field $name from header: not found.

You ask to remove a field which is not known in the header.  Using
M<delete()>, M<reset()>, or M<set()> to do the job will not result
in warnings: those methods check the existence of the field first.

=cut

sub removeField($)
{   my ($self, $field) = @_;
    my $name = $field->name;

    my $known = $self->{MMH_fields};

    if(!defined $known->{$name})
    { ; }  # complain
    elsif(ref $known->{$name} eq 'ARRAY')
    {    for(my $i=0; $i < @{$known->{$name}}; $i++)
         {
             return splice @{$known->{$name}}, $i, 1
                 if $known->{$name}[$i] eq $field;
         }
    }
    elsif($known->{$name} eq $field)
    {    return delete $known->{$name};
    }

    $self->log(WARNING => "Cannot remove field $name from header: not found.");

    return;
}

#------------------------------------------

=method print [FILEHANDLE]

Print all headers to the specified FILEHANDLE, by default the selected
filehandle.  See M<printUndisclosed()> to limit the headers to include
only the public headers.

=examples

 $head->print(\*OUT);
 $head->print;

 my $fh = IO::File->new(...);
 $head->print($fh);

=cut

sub print(;$)
{   my $self  = shift;
    my $fh    = shift || select;

    $_->print($fh)
        foreach $self->orderedFields;

    $fh->print("\n");

    $self;
}

#------------------------------------------

=method printUndisclosed [FILEHANDLE]

Like the usual M<print()>, the header lines are printed to the specified
FILEHANDLE, by default the selected filehandle.  In this case, however,
C<Bcc> and C<Resent-Bcc> lines are included.

=cut

sub printUndisclosed($)
{   my ($self, $fh) = @_;

    $_->print($fh)
       foreach grep {$_->toDisclose} $self->orderedFields;

    $fh->print("\n");

    $self;
}

#------------------------------------------

=method string

Returns the whole header as one scalar (in scalar context) or list
of lines (list context).  Triggers completion.

=cut

sub toString() {shift->string}
sub string()
{   my $self  = shift;

    my @lines = map {$_->string} $self->orderedFields;
    push @lines, "\n";

    wantarray ? @lines : join('', @lines);
}

#------------------------------------------

=method resentGroups

Returns a list of M<Mail::Message::Head::ResentGroup> objects which
each represent one intermediate point in the message's transmission in
the order as they appear in the header: the most recent one first.

A resent group contains a set of header fields whose names start
with C<Resent->.  Before the first C<Resent> line is I<trace> information,
which is composed of an optional C<Return-Path> field and an required
C<Received> field.

=cut

sub resentGroups()
{   my $self = shift;
    my (@groups, $return_path, $delivered_to, @fields);
    require Mail::Message::Head::ResentGroup;

    foreach my $field ($self->orderedFields)
    {   my $name = $field->name;
        if($name eq 'return-path')              { $return_path = $field }
        elsif($name eq 'delivered-to')          { $delivered_to = $field }
        elsif(substr($name, 0, 7) eq 'resent-') { push @fields, $field }
        elsif($name eq 'received')
        {   push @groups, Mail::Message::Head::ResentGroup->new
               (@fields, head => $self)
                   if @fields;

            @fields = $field;
            unshift @fields, $delivered_to if defined $delivered_to;
            undef $delivered_to;

            unshift @fields, $return_path  if defined $return_path;
            undef $return_path;
        }
    }

    push @groups, Mail::Message::Head::ResentGroup->new(@fields, head => $self)
          if @fields;

    @groups;
}

#------------------------------------------

=method addResentGroup RESENT-GROUP|DATA

Add a RESENT-GROUP (a M<Mail::Message::Head::ResentGroup> object) to
the header.  If you specify DATA, that is used to create such group
first.  If no C<Received> line is specified, it will be created
for you.

These header lines have nothing to do with the user's sense
of C<reply> or C<forward> actions: these lines trace the e-mail
transport mechanism.

=examples

 my $rg = Mail::Message::Head::ResentGroup->new(head => $head, ...);
 $head->addResentGroup($rg);

 my $rg = $head->addResentGroup(From => 'me');

=cut

sub addResentGroup(@)
{   my $self  = shift;

    require Mail::Message::Head::ResentGroup;
    my $rg = @_==1 ? (shift)
      : Mail::Message::Head::ResentGroup->new(@_, head => $self);

    my @fields = $rg->orderedFields;
    my $order  = $self->{MMH_order};

    my $i;
    for($i=0; $i < @$order; $i++)
    {   next unless defined $order->[$i];
        last if $order->[$i]->name =~ m!^(?:received|return-path|resent-)!;
    }

    my $known = $self->{MMH_fields};
    while(@fields)
    {   my $f    = pop @fields;
        splice @$order, $i, 0, $f;
        weaken( $order->[$i] );
        my $name = $f->name;

        # Adds *before* in the list.
           if(!defined $known->{$name})      {$known->{$name} = $f}
        elsif(ref $known->{$name} eq 'ARRAY'){unshift @{$known->{$name}},$f}
        else                       {$known->{$name} = [$f, $known->{$name}]}
    }

    $self->modified(1);
    $rg;
}

#------------------------------------------

=section About the body

=method timestamp

Will return a good indication of about when the message was send, with as
little guessing as possible.  The timestamp is encoded as C<time> is
on your system (see perldoc -f time), and as such usable for the C<gmtime>
and C<localtime> methods.

=cut


sub timestamp() {shift->guessTimestamp || time}

#------------------------------------------

=method guessTimeStamp

Make a guess about when the message was origanally posted, based on the
information found in the header.

For some kinds of folders, M<Mail::Message::guessTimestamp()> may produce
a better result, for instance by looking at the modification time of the
file in which the message is stored.  Also some protocols, like POP can
supply that information.

=cut

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = Mail::Message::Field->dateToTimestamp($date);
    }

    unless($stamp)
    {   foreach (reverse $self->get('received'))
        {   $stamp = Mail::Message::Field->dateToTimestamp($_->comment);
            last if $stamp;
        }
    }

    $self->{MBM_timestamp} = $stamp;
}

#------------------------------------------

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->get('Lines');   # 40 chars per lines
    return $1 * 40   if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#------------------------------------------

=section Internals

=method createFromLine

For some mail-folder types separate messages by a line starting with
'C<From >'.  If a message is moved to such folder from a folder-type
which does not support these separators, this method is called to produce
one.

=cut

sub createFromLine()
{   my $self   = shift;

    my $from   = $self->get('from') || '';
    my $stamp  = $self->timestamp;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
}

#------------------------------------------

=method createMessageId

Creates a message-id for this message.  This method will be run when
a new message is created, or a message is discovered without the
message-id header field.  Message-ids are required for detection of
message-threads.  See M<messageIdPrefix()>.

=cut

my $unique_id     = time;
my $hostname;

sub createMessageId()
{   my $mid = shift->messageIdPrefix . '-' . $unique_id++;

    unless(defined $hostname)
    {   require Sys::Hostname;
        $hostname = Sys::Hostname::hostname() || 'localhost';
    }

    $mid . '@' . $hostname;
}

#------------------------------------------

=method messageIdPrefix [STRING]

Sets/returns the message-id start.  The rest of the message-id is an
integer which is derived from the current time and the local host.
See M<createMessageId()>.

=cut

our $unique_prefix;

sub messageIdPrefix(;$)
{   my $self = shift;
    return $unique_prefix if !@_ && defined $unique_prefix;

    $unique_prefix = shift || "mailbox-$$";
}

#------------------------------------------

1;
