use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Date::Parse;

=head1 NAME

Mail::Message::Head::Complete - the header of one message

=head1 SYNOPSIS

 my $head = Mail::Message::Head::Complete->new;
 See Mail::Message::Head

=head1 DESCRIPTION

A mail's message can be in various states: unread, partially read, and
fully read.  The class stores a message of which all header lines are
known for sure.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=cut

#------------------------------------------

=head2 The Header

=cut

#------------------------------------------

sub isDelayed() {0}

#------------------------------------------

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

    foreach my $name ($self->grepNames(@_))
    {   $copy->add($_->clone) foreach $self->get($name);
    }

    $copy;
}

#------------------------------------------

=head2 Constructing a Header

=cut

#------------------------------------------

=method add FIELD | LINE | NAME, BODY [,COMMENT]

Add a field to the header.  If a field is added more than once, all values
are stored in the header, in the order they are added.

The return value of this method is the Mail::Message::Field object
which is created (or was specified).  Triggers Completion.

=examples

 my $head  = Mail::Message::Head->new;
 $head->add('Subject: hi!');
 $head->add(From => 'me@home');
 my $field = Mail::Message::Field->new('To: you@there');
 $head->add($field);
 my Mail::Message::Field $s = $head->add(Sender => 'I');

=cut

sub add(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else { $field = $type->new(@_) }

    $field->setWrapLength($self->{MMH_wrap_length});

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

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

=method set FIELD | LINE | NAME, BODY [,COMMENT]

The C<set> method is similar to the add() method, and takes the same
options. However, existing values for fields will be removed before a new
value is added.

=cut

my @skip_none = qw/content-transfer-encoding content-disposition/;
my %skip_none = map { ($_ => 1) } @skip_none;

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else
    {   $field = $type->new(@_);
    }

    my $name  = $field->name;         # is already lower-cased
    my $known = $self->{MMH_fields};

    # Internally, non-existing content-info are in the body stored as 'none'
    # The header will not contain these lines.

    if($skip_none{$name} && $field->body eq 'none')
    {   delete $known->{$name};
        return $field;
    }

    # Put it in place.

    $field->setWrapLength($self->{MMH_wrap_length});

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $self->{MMH_modified}++;

    $field;
}

#------------------------------------------

=method reset NAME, FIELDS

Replace the values in the header fields named by NAME with the values
specified in the list of FIELDS. A single name can correspond to multiple
repeated fields.

If FIELDS is empty, the corresponding NAME fields will
be removed. The location of removed fields in the header order will be
remembered. Fields with the same name which are added later will appear at
the remembered position.  This is equivalent to the delete() method.

=examples

 # reduce number of 'Received' lines to last 5)
 my @received = $head->get('Received');
 $head->reset('Received', @received[-5..-1]) if @received > 5;

=cut

sub reset($@)
{   my ($self, $name) = (shift, lc shift);
    my $known = $self->{MMH_fields};

    if(@_==0)    { undef $known->{$name}  }
    elsif(@_==1) { $known->{$name} = shift }
    else         { $known->{$name} = [@_]  }

    $self->{MMH_modified}++;
    $self;
}
 
#------------------------------------------

=method delete NAME

Remove the field with the specified name.  If the header contained
multiple lines with the same name, they will be replaced all together.
This method simply calls reset().

=cut

sub delete($) { $_[0]->reset($_[1]) }

#------------------------------------------

=head2 Access to the Header

=cut

#------------------------------------------

=method count NAME

Count the number of fields with this NAME.  Most fields will return 1: only one
occurance in the header.  As example, the C<Received> fields are usually present
more than once.

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
    {   # I love this tric:
        local $" = ')|(?:';
        $take    = qr/^(?:(?:@take))/i;
    }

    grep {$_ =~ $take} $self->names;
}

#------------------------------------------

=method print [FILEHANDLE]

Print all headers to the specified FILEHANDLE, by default the selected
filehandle.  See printUndisclosed() to limit the headers to include
only the public headers.

=examples

 $head->print(\*OUT);
 $head->print;

 my $fh = FileHandle->new(...);
 $head->print($fh);

=cut

sub print(;$)
{   my $self  = shift;
    my $fh    = shift || select;

    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");

    $self;
}

#------------------------------------------

=method printUndisclosed [FILEHANDLE]

Like the usual print(), the header lines are printed to the specified
FILEHANDLE, by default the selected filehandle.  In this case, however,
C<Bcc> and C<Resent-Bcc> lines are included.

=cut

sub printUndisclosed($)
{   my ($self, $fh) = @_;

    my $known = $self->{MMH_fields};
    foreach my $name (@{$self->{MMH_order}})
    {   next if $name eq 'Resent-Bcc' || $name eq 'Bcc';
        my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");
    $self;
}

#------------------------------------------

=method toString

Returns the whole header as one scalar (in scalar context) or list
of lines (list context).  Triggers completion.

=cut

sub toString()
{   my $self  = shift;
    my $known = $self->{MMH_fields};

    my @lines;
    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        push @lines, $_->toString foreach @this;
    }

    push @lines, "\n";
    wantarray ? @lines : join('', @lines);
}

#------------------------------------------

=method nrLines

Return the number of lines needed to display this header (including
the trailing newline)

=cut

sub nrLines()
{   my $self = shift;
    my $nr   = 1;  # trailing

    foreach my $name ($self->names)
    {   $nr += $_->nrLines foreach $self->get($name);
    }

    $nr;
}

#------------------------------------------

=method size

Return the number of bytes needed to display this header (including
the trailing newline).

=cut

sub size()
{   my $self  = shift;
    my $bytes = 1;  # trailing blank
    foreach my $name ($self->names)
    {   $bytes += $_->size foreach $self->get($name);
    }
    $bytes;
}

#------------------------------------------

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

For some kinds of folders, Mail::Box::guessTimestamp() may produce a better
result, for instance by looking at the modification time of the file in
which the message is stored.  Also some protocols, like POP can supply that
information.

=cut

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach (reverse $self->get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MBM_timestamp} = $stamp;
}

#------------------------------------------

=method guessBodySize

Try to estimate the size of the body of this message, but without parsing
the header or body.  The result might be C<undef> or a few percent of
the real size.  It may even be very far of the real value, that's why
this is a guess.

=cut

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->get('Lines');   # 40 chars per lines
    return $1 * 40   if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

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
message-threads.

=cut

my $unique_id = time;

sub createMessageId() { 'mailbox-'.$unique_id++ }

1;
