use strict;
use warnings;

package Mail::Message::Head;
use base 'Mail::Reporter';

use Mail::Message::Field;
use Mail::Box::Parser;

use Carp;

our $VERSION = '2.00_02';

#use overload qq("") => 'toString';

=head1 NAME

Mail::Message::Head - UNDER CONSTRUCTION: the header of one Mail::Message

=head1 SYNOPSIS

   my $head = Mail::Message::Head->new;
   $head->add('From: me@localhost');
   $head->add(From => 'me@localhost');
   $head->add(Mail::Message::Field->new(From => 'me'));
   my Mail::Message::Field $subject = $head->get('subject');
   my Mail::Message::Field @rec = $head->get('received');
   $head->delete('From');

=head1 DESCRIPTION

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message header object.  The object will store all the
fields of a header.  When you get information from the header, it
will be returned to you as C<Mail::Message::Field>-objects, although
it may be that it is internally stored differently.

The following options can be specified:

=over 4

=item * field_type =E<gt> CLASS

The type of objects that all the fields will have.  This must be
an extention of C<Mail::Message::Field>.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMH_field_type} = $args->{field_type} || 'Mail::Message::Field';
    $self->{MMH_fields}     = {};
    $self->{MMH_order}      = [];
    $self;
}

#------------------------------------------

=item add FIELD

=item add LINE

=item add NAME, BODY [,COMMENT]

Add a field to the header.  If a field is added more than once, the
all values are stored in the header, in the order they are added.

The return of this method is the C<Mail::Message::Field>-object
which has been created (or was specified).

Examples:

   my $head  = Mail::Message::Head->new;
   $head->add('Subject: hi!');
   $head->add(From => 'me@home');
   my $field = Mail::Message::Field->new('To: you@there');
   $head->add($field);
   my Mail::Message::Field $s = $head->add(Sender => 'I');

=cut

sub add(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type};

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

    $field;
}

sub setField($$) {shift->add(@_)} # compatibility

#------------------------------------------

=item set FIELD

=item set LINE

=item set NAME, BODY [,COMMENT]

Same possibilities as with C<add()>, but eventually existing values
for the field will be removed, before setting this new value.

=cut

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type};

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

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $field;
}

#------------------------------------------

=item get NAME [,INDEX]

Get the data which is related to the field with the NAME.  The case of the
characters in NAME does not case.

If there is only one element defined for this field, or there is an INDEX
specified as second argument, you will get that element.  Otherwise, if
this field was found more than one in the header, you get all values (in
order as read) in LIST-context and the last value in SCALAR-context.

Example:

    my $head = Mail::Message::Head->new;
    $head->add('Received: abc');
    $head->add('Received: xyz');
    $head->add('Subject: greetings');

    my @rec_list   = $head->get('Received');
    my $rec_scalar = $head->get('Received');
    print ",@rec_list,$rec_scalar,"     # ,abc xyz, xyz,
    print $head->get('Received', 0);    # abc

    my @sub_list   = $head->get('Subject');
    my $sub_scalar = $head->get('Subject');
    print ",@sub_list,$sub_scalar,"     # ,greetings, greetings,

=cut

sub get($;$)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};
    my $index = shift;

    if(defined $index)
    {   return ! defined $value      ? undef
             : ref $value eq 'ARRAY' ? $value->[$index]
             : $index == 0           ? $value
             :                         undef;
    }
    elsif(wantarray)
    {   return ! defined $value      ? ()
             : ref $value eq 'ARRAY' ? @$value
             :                         ($value);
    }
    else
    {   return ! defined $value      ? undef
             : ref $value eq 'ARRAY' ? $value->[-1]
             :                         $value;
    }
}

sub get_all(@) { my @all = shift->get(@_) }   # compatibility, force list

#------------------------------------------

=item count NAME

Count the number of fields for this NAME.

=cut

sub count($)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};

      ! defined $value ? 0
    : ref $value       ? @$value
    :                    1;
}

#------------------------------------------

=item reset NAME, FIELDS

Set the values for one field (a field can be present in the header
more than once) to the specified list.  For instance, if you want
to remove a few of the items.

If your list is empty, the field will be removed, although its original
location in the header-order remembered.  Later added fields with the
name will appear on that location in the printing order.

Examples:

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

    $self;
}
 
#------------------------------------------

=item names

Returns a full ordered list of all field-names, as defined in this
header.  Fields which were C<set()> to be empty will still be
listed here.

=cut

sub names() { @{shift->{MMH_order}} }

#------------------------------------------

=item load

Force all header information to be loaded.  If all information is
already known, this call will have no effect.  In any case, it
returns the header-object.

=cut

sub load() {shift}

#------------------------------------------

=item isDelayed

Returns whether some information from the header may be missing: whether
the parsing was delayed or only partial.  Returns false when all header
data is known.

=cut

sub isDelayed { 0 }

#------------------------------------------

=item print FILE [,CHARS]

Print the header to the specified FILE, where the lines should
be foldered into a preferred length of CHARacterS.

Example:

    $head->print(\*STDOUT);

    my $fh = FileHandle->new(...);
    $head->print($fh, 65);

=cut

sub print($;$)
{   my ($self, $fh, @options) = @_;
    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh, @options) foreach @this;
    }

    $self;
}

#------------------------------------------

=item read PARSER

Read the header-information of one message into this header structure.  This
method is called by the folder object (some C<Mail::Box> sub-class), which
passes the PARSER as argument.  Not a method to call yourself!

=cut

sub read($)
{   my ($self, $parser) = @_;
    my @pairs = $parser->readHeader;

    $self->fromLine(shift @pairs);

    while(@pairs)
    {   my $name = lc (shift @pairs);
        $self->add($name, shift @pairs);
    }

    $self;
}

#------------------------------------------

=item fromLine [STRING]

Get (or set) the line which works as seperator-line in Mbox-type
folders.

=cut

sub fromLine(;$)
{   my $self = shift;
    @_ ? $self->{MMH_fromline} = shift : $self->{MMH_fromline};
}

#------------------------------------------

=item guessBodySize

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
    return $1*40 if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#------------------------------------------

=item guessTimestamp

Try to get a good guess about the time this message was transmitted.  This
moment may be somewhere from start of transmission by the sender till
receipt.  It may return C<undef>.

=cut

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach ($self->get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MBM_timestamp} = $stamp;
}


#------------------------------------------

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 2.00_02, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Message>
L<Mail::Box::Manager>

=cut

1;
