use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;
use Mail::Message::Head::Partial;

use Scalar::Util 'weaken';
use List::Util   'sum';

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

=method build [PAIR|FIELD]-LIST
=warning Field objects have an implied name ($name)
=cut

sub build(@)
{   my $self = shift;
    my $head = $self->new;
    while(@_)
    {   my $name = shift;

        if($name->isa('Mail::Message::Field'))
        {   $head->add($name);
            next;
        }

        my $content = shift;
        if(ref $content && $content->isa('Mail::Message::Field'))
        {   $self->log(WARNING => "Field objects have an implied name ($name)");
            $head->add($content);
            next;
        }

        $head->add($name, $content);
    }

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

=method wrap INTEGER
Re-fold all fields from the header to contain at most INTEGER number of
characters per line.

=example re-folding a header
 $msg->head->wrap(78);
=cut

sub wrap($)
{   my ($self, $length) = @_;
    $_->setWrapLength($length) foreach $self->orderedFields;
}

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
adviced to let MailBox do the folding for you.

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

Filter from all header fields the names which start will any of the
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
value is added.  READ THE IMPORTANT WARNING IN M<removeField()>
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
repeated fields.  READ THE IMPORTANT WARNING IN M<removeField()>

Removing fields which are part of one of the predefined field groups is
not a smart idea.  You can better remove these fields as group, all
together.  For instance, the C<'Received'> lines are part of resent
groups, C<'X-Spam'> is past of a spam group, and C<List-Post> belongs
to a list group.  You can delete a whole group with
M<Mail::Message::Head::FieldGroup::delete()>, or with methods which
are provided by M<Mail::Message::Head::Partial>.

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
READ THE IMPORTANT WARNING IN M<removeField()>

=cut

sub delete($) { $_[0]->reset($_[1]) }

#------------------------------------------

=method removeField FIELD

Remove the specified FIELD object from the header.  This is useful when
there are possible more than one fields with the same name, and you
need to remove exactly one of them.  Also have a look at M<delete()>,
M<reset()>, and M<set()>.

See also M<Mail::Message::Head::Partial::removeFields()> (mind the 's'
at the end of the name), which accepts a string or regular expression
as argument to select the fields to be removed.

WARNING WARNING WARNING: for performance reasons, the header administration
uses weak references (see L<Scalar::Util> method weaken()> to figure-out
which fields have been removed.  A header is a hash of field for fast search
and an array of weak references to remember the order of the fields, required
for printing.  If the field is removed from the hash, the weak-ref is set to
undef and the field not printed.

However... it is easy to disturb this process.  Example:
 my $msg = ....;                 # subject ref-count = 1 + 0 = 1
 $msg->head->delete('Subject');  # subject ref-count =     0 = 0: clean-up
 $msg->print;                    # subject doesn't show: ok

But
 my $msg = ....;                 # subject ref-count = 1 + 0 = 1
 my $s = $msg->head->get('subject'); # ref-count = 1 + 1 + 0 = 2
 $msg->head->delete('Subject');  # subject ref-count = 1 + 0 = 1: no clean-up
 $msg->print;                    # subject DOES show: not ok
 undef $s;                       # ref-count becomes 0: clean-up
 $msg->print;                    # subject doesn't show: ok

To avoid the latter situation, do not catch the field object, but only
the field content.  SAVE are all methods which return the text:
 my $s = $msg->head->get('subject')->body;
 my $s = $msg->head->get('subject')->unfoldedBody;
 my $s = $msg->head->get('subject')->foldedBody;
 my $s = $msg->head->get('subject')->foldedBody;
 my $s = $msg->get('subject');
 my $s = $msg->subject;
 my $s = $msg->string;

=warning Cannot remove field $name from header: not found.
You ask to remove a field which is not known in the header.  Using
M<delete()>, M<reset()>, or M<set()> to do the job will not result
in warnings: those methods check the existence of the field first.

=cut

sub removeField($)
{   my ($self, $field) = @_;
    my $name  = $field->name;
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

=method removeFields STRING|REGEXP, [STRING|REGEXP, ...]

The header object is turned into a M<Mail::Message::Head::Partial> object
which has a set of fields removed.  Read about the implications and the
possibilities in M<Mail::Message::Head::Partial::removeFields()>.

=cut

sub removeFields(@)
{   my $self = shift;
    (bless $self, 'Mail::Message::Head::Partial')->removeFields(@_);
}
   
#------------------------------------------

=method removeFieldsExcept STRING|REGEXP, [STRING|REGEXP, ...]

The header object is turned into a M<Mail::Message::Head::Partial> object
which has a set of fields removed.  Read about the implications and the
possibilities in M<Mail::Message::Head::Partial::removeFieldsExcept()>.

=cut

sub removeFieldsExcept(@)
{   my $self = shift;
    (bless $self, 'Mail::Message::Head::Partial')->removeFieldsExcept(@_);
}

#------------------------------------------

=method removeContentInfo
Remove all body related fields from the header.  The header will become
partial.

=cut

sub removeContentInfo() { shift->removeFields(qr/^Content-/, 'Lines') }

#------------------------------------------

=method removeResentGroups

Removes all resent groups at once.  The header object is turned into
a M<Mail::Message::Head::Partial> object.  Read about the implications and the
possibilities in M<Mail::Message::Head::Partial::removeResentGroups()>.

=cut

sub removeResentGroups(@)
{   my $self = shift;
    (bless $self, 'Mail::Message::Head::Partial')->removeResentGroups(@_);
}

#------------------------------------------

=method removeListGroup

Removes all fields related to mailing list administration at once.
The header object is turned into a M<Mail::Message::Head::Partial>
object.  Read about the implications and the possibilities in
M<Mail::Message::Head::Partial::removeListGroup()>.

=cut

sub removeListGroup(@)
{   my $self = shift;
    (bless $self, 'Mail::Message::Head::Partial')->removeListGroup(@_);
}

#------------------------------------------

=method removeSpamGroups

Removes all fields which were added by various spam detection software
at once.  The header object is turned into a M<Mail::Message::Head::Partial>
object.  Read about the implications and the possibilities in
M<Mail::Message::Head::Partial::removeSpamGroups()>.

=cut

sub removeSpamGroups(@)
{   my $self = shift;
    (bless $self, 'Mail::Message::Head::Partial')->removeSpamGroups(@_);
}

#------------------------------------------

=method spamDetected
Returns whether one of the spam groups defines a report about spam.  If there
are not header fields in the message which relate to spam-detection
software, C<undef> is returned.  The spamgroups which report spam are returned.

=examples
 $message->delete if $message->spamDetected;

 call_spamassassin($message)
    unless defined $message->spamDetected;

=cut

sub spamDetected()
{   my $self = shift;
    my @sgs = $self->spamGroups or return undef;
    grep { $_->spamDetected } @sgs;
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

    if(ref $fh eq 'GLOB') { print $fh "\n" }
    else                  { $fh->print("\n") }

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

    if(ref $fh eq 'GLOB') { print $fh "\n" }
    else                  { $fh->print("\n") }

    $self;
}

#------------------------------------------

=method printSelected FILEHANDLE, (STRING|REGEXP)s
                                                                                
Like the usual M<print()>, the header lines are printed to the specified
FILEHANDLE.  In this case, however, only the fields with names as specified by
STRING (case insensative) or REGEXP are printed.  They will stay the in-order
of the source header.

=example printing only a subset of the fields
 $head->printSelected(STDOUT, qw/Subject From To/, qr/^x\-(spam|xyz)\-/i)

=cut
                                                                                
sub printSelected($@)
{   my ($self, $fh) = (shift, shift);

    foreach my $field ($self->orderedFields)
    {   my $Name = $field->Name;
        my $name = $field->name;

        my $found;
        foreach my $pattern (@_)
        {   $found = ref $pattern?($Name =~ $pattern):($name eq lc $pattern);
            last if $found;
        }

           if(!$found)           { ; }
        elsif(ref $fh eq 'GLOB') { print $fh "\n" }
        else                     { $fh->print("\n") }
    }
                                                                                
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
See also M<addResentGroup()> and M<removeResentGroups()>.

A resent group contains a set of header fields whose names start
with C<Resent->.  Before the first C<Resent> line is I<trace> information,
which is composed of an optional C<Return-Path> field and an required
C<Received> field.

=cut

sub resentGroups()
{   my $self = shift;
    require Mail::Message::Head::ResentGroup;
    Mail::Message::Head::ResentGroup->from($self);
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
    my $rg = @_==1 ? (shift) : Mail::Message::Head::ResentGroup->new(@_);

    my @fields = $rg->orderedFields;
    my $order  = $self->{MMH_order};

    # Look for the first line which relates to resent groups
    my $i;
    for($i=0; $i < @$order; $i++)
    {   next unless defined $order->[$i];
        last if $rg->isResentGroupFieldName($order->[$i]->name);
    }

    my $known = $self->{MMH_fields};
    while(@fields)
    {   my $f    = pop @fields;

        # Add to the order of fields
        splice @$order, $i, 0, $f;
        weaken( $order->[$i] );
        my $name = $f->name;

        # Adds *before* in the list for get().
           if(!defined $known->{$name})      {$known->{$name} = $f}
        elsif(ref $known->{$name} eq 'ARRAY'){unshift @{$known->{$name}},$f}
        else                       {$known->{$name} = [$f, $known->{$name}]}
    }

    $rg->messageHead($self);

    # Oh, the header has changed!
    $self->modified(1);

    $rg;
}

#------------------------------------------

=method listGroup

Returns a I<list group> description: the set of headers which form
the information about mailing list software used to transport the
message.  See also M<addListGroup()> and M<removeListGroup()>.

=example use of listGroup()

 if(my $lg = $msg->head->listGroup)
 {  $lg->print(\*STDERR);
    $lg->delete;
 }

 $msg->head->removeListGroup;

=cut

sub listGroup()
{   my $self = shift;
    eval "require 'Mail::Message::Head::ListGroup'";
    Mail::Message::Head::ListGroup->from($self);
}

#------------------------------------------

=method addListGroup OBJECT

A I<list group> is a set of header fields which contain data about a
mailing list which was used to transmit the message.  See
M<Mail::Message::Head::ListGroup> for details about the implementation
of the OBJECT.

When you have a list group prepared, you can add it later using this
method.  You will get your private copy of the list group data in
return, because the same group can be used for multiple messages.

=example of adding a list group to a header

 my $lg = M<Mail::Message::Head::ListGroup>->new(...);
 my $own_lg = $msg->head->addListGroup($lg);

=cut

sub addListGroup($)
{   my ($self, $lg) = @_;
    $lg->attach($self);
}

#------------------------------------------

=method spamGroups [NAMES]

Returns a list of M<Mail::Message::Head::SpamGroup> objects, each collecting
some lines which contain spam fighting information.  When any NAMES are
given, then only these groups are returned.
See also M<addSpamGroup()> and M<removeSpamGroups()>.

In scalar context, with exactly one NAME specified, that group will be
returned.  With more NAMES or without NAMES, a list will be returned
(which defaults to the length of the list in scalar context).

=example use of listGroup()

 my @sg = $msg->head->spamGroups;
 $sg[0]->print(\*STDERR);
 $sg[-1]->delete;

 my $sg = $msg->head->spamGroups('SpamAssassin');

=cut

sub spamGroups(@)
{   my $self = shift;
    require Mail::Message::Head::SpamGroup;
    my @types = @_ ? (types => \@_) : ();
    my @sgs   = Mail::Message::Head::SpamGroup->from($self, @types);
    wantarray || @_ != 1 ? @sgs : $sgs[0];
}

#------------------------------------------

=method addSpamGroup OBJECT

A I<spam fighting group> is a set of header fields which contains data
which is used to fight spam.  See M<Mail::Message::Head::SpamGroup>
for details about the implementation of the OBJECT.

When you have a spam group prepared, you can add it later using this
method.  You will get your private copy of the spam group data in
return, because the same group can be used for multiple messages.

=example of adding a spam group to a header

 my $sg = M<Mail::Message::Head::SpamGroup>->new(...);
 my $own_sg = $msg->head->addSpamGroup($sg);

=cut

sub addSpamGroup($)
{   my ($self, $sg) = @_;
    $sg->attach($self);
}

#------------------------------------------

=section About the body

=method timestamp

Returns an indication about when the message was sent, with as
little guessing as possible.  In this case, the date as specified by the
sender is trusted.  See M<recvstamp()> when you do not want to trust the
sender.

The timestamp is encoded as C<time> is
on your system (see perldoc -f time), and as such usable for the C<gmtime>
and C<localtime> methods.

=cut


sub timestamp() {shift->guessTimestamp || time}

#------------------------------------------

=method recvstamp

Returns an indication about when the message was sent, but only using the
C<Date> field in the header as last resort: we do not trust the sender of
the message to specify the correct date.  See M<timestamp()> when you do
trust the sender.

Many spam producers fake a date, which mess up the order of receiving
things.  The timestamp which is produced is derived from the Received
headers, if they are present, and C<undef> otherwise.

The timestamp is encoded as C<time> is on your system (see perldoc -f
time), and as such usable for the C<gmtime> and C<localtime> methods.

=example of time-sorting folders with received messages
 my $folder = $mgr->open('InBox');
 my @messages = sort {$a->recvstamp <=> $b->recvstamp}
                   $folder->messages;

=example of time-sorting messages of mixed origin
 my $folder = $mgr->open('MyFolder');

 # Pre-calculate timestamps to be sorted (for speed)
 my @stamps = map { [ ($_->timestamp || 0), $_ ] }
                     $folder->messages;

 my @sorted
   = map { $_->[1] }      # get the message for the stamp
       sort {$a->[0] <=> $b->[0]}   # stamps are numerics
          @stamps;

=cut

sub recvstamp()
{   my $self = shift;

    return $self->{MMH_recvstamp} if exists $self->{MMH_recvstamp};

    my $recvd = $self->get('received', 0) or
        return $self->{MMH_recvstamp} = undef;

    my $stamp = Mail::Message::Field->dateToTimestamp($recvd->comment);

    $self->{MMH_recvstamp} = defined $stamp && $stamp > 0 ? $stamp : undef;
}

#------------------------------------------

=method guessTimeStamp

Make a guess about when the message was origanally posted, based on the
information found in the header's C<Date> field.

For some kinds of folders, M<Mail::Message::guessTimestamp()> may produce
a better result, for instance by looking at the modification time of the
file in which the message is stored.  Also some protocols, like POP can
supply that information.

=cut

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if exists $self->{MMH_timestamp};

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

    $self->{MMH_timestamp} = defined $stamp && $stamp > 0 ? $stamp : undef;
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
    my $sender = $from =~ m/(\<.*?\>)/ ? $1 : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
}

#------------------------------------------

=method createMessageId

Creates a message-id for this message.  This method will be run when
a new message is created, or a message is discovered without the
message-id header field.  Message-ids are required for detection of
message-threads.  See M<messageIdPrefix()>.

=cut

my $msgid_creator;

sub createMessageId()
{   $msgid_creator ||= $_[0]->messageIdPrefix;
    $msgid_creator->(@_);
}

#------------------------------------------

=ci_method messageIdPrefix [PREFIX, [HOSTNAME]|CODE]

When options are provided, it sets a new way to create message-ids,
as used by M<createMessageId()>.  You have two choices: either by
providing a PREFIX and optionally a HOSTNAME, or a CODE reference.

The CODE reference will be called with the header as first argument.
You must ensure yourself that the returned value is RFC compliant.

The PREFIX defaults to C<mailbox-$$>, the HOSTNAME defaults to the
return of L<Sys::Hostname>'s method C<hostname()>.  Inbetween the
two, a nano-second time provided by L<Time::Hires> is used.  If that
module is not available, C<time> is called at the start of the program,
and incremented for each newly created id.

In any case, a subroutine will be created to be used.  A reference
to that will be returned.  When the method is called without arguments,
but no subroutine is defined yet, one will be created.

=examples setting a message prefix
  $head->messageIdPrefix('prefix');
  Mail::Message::Head::Complete->messageIdPrefix('prefix');
  my $code = $head->messageIdPrefix('mailbox', 'nohost');

  sub new_msgid()
  {   my $head = shift;
      "myid-$$-${(rand 10000)}@example.com";
  }

  $many_msg->messageIdPrefix(\&new_msgid);
  Mail::Message::Head::Complete->messageIdPrefix(&new_msgid);
 
=cut

sub messageIdPrefix(;$$)
{   my $thing = shift;
    return $msgid_creator
       unless @_ || !defined $msgid_creator;

    return $msgid_creator = shift
       if @_==1 && ref $_[0] eq 'CODE';

    my $prefix   = shift || "mailbox-$$";

    my $hostname = shift;
    unless(defined $hostname)
    {   require Sys::Hostname;
        $hostname = Sys::Hostname::hostname() || 'localhost';
    }

    eval {require Time::HiRes};
    if(Time::HiRes->can('gettimeofday'))
    {
        return $msgid_creator
          = sub { my ($sec, $micro) = Time::HiRes::gettimeofday();
                  "$prefix-$sec-$micro\@$hostname";
                };
    }

    my $unique_id = time;
    $msgid_creator
      = sub { $unique_id++;
              "$prefix-$unique_id\@$hostname";
            };
}

1;
