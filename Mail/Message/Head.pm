use strict;
use warnings;

package Mail::Message::Head;
use base 'Mail::Reporter';

use Mail::Message::Head::Complete;
use Mail::Message::Field::Fast;

use Carp;
use Scalar::Util 'weaken';

use overload qq("") => 'string_unless_carp'
           , bool   => 'isEmpty';

=head1 NAME

Mail::Message::Head - the header of one message

=head1 SYNOPSIS

 my $head = Mail::Message::Head->new;
 $head->add('From: me@localhost');
 $head->add(From => 'me@localhost');
 $head->add(Mail::Message::Field->new(From => 'me'));
 my Mail::Message::Field $subject = $head->get('subject');
 my Mail::Message::Field @rec = $head->get('received');
 $head->delete('From');

=head1 DESCRIPTION

Mail::Message::Head MIME headers are part of Mail::Message messages,
which are stored by Mail::Box folders.

The header of a MIME message object contains a set of lines, which are
called I<fields> (by default represented by Mail::Message::Field
objects).  Dependent on the situation, the knowledge about the fields can
be in one of three situations, each represented by a sub-class of this
module:

=over 4

=item * Mail::Message::Head::Complete

In this case, it is sure that all knowledge about the header is available.
When you get() information from the header and it is not there, it will
never be there.

=item * Mail::Message::Head::Subset

There is no certainty whether all header lines are known (probably not).  This
may be caused as result of reading a fast index file, as described in
Mail::Box::MH::Index.  The object is automatically transformed
into a Mail::Message::Head::Complete when all header lines must be known.

=item * Mail::Message::Head::Delayed

In this case, there is no single field known.  Access to this header will
always trigger the loading of the full header.

=back

On this page, the general methods which are available on any header are
described.  Read about differences in the sub-class specific pages.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

Create a new message header object.  The object will store all the
fields of a header.  When you get information from the header, it
will be returned to you as Mail::Message::Field objects, although
the fields may be stored differently internally.

If you try to instantiate a Mail::Message::Head, you will automatically
be upgraded to a Mail::Message::Head::Complete --a full head.

=option  modified BOOLEAN
=default modified <false>

=option  field_type CLASS
=default field_type 'Mail::Message::Field::Fast'

The type of objects that all the fields will have.  This must be
an extension of Mail::Message::Field.

=option  message MESSAGE
=default message undef

The MESSAGE where this header belongs to.  Usually, this is not known
at creation of the header, but sometimes it is.  If not, call the
message() method later to set it.

=cut

sub new(@)
{   my $class = shift;

    return Mail::Message::Head::Complete->new(@_)
       if $class eq __PACKAGE__;

    $class->SUPER::new(@_);
}
      
sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MMH_field_type} = $args->{field_type}
        if $args->{field_type};

    $self->message($args->{message})
        if defined $args->{message};

    $self->{MMH_fields}     = {};
    $self->{MMH_order}      = [];
    $self->{MMH_modified}   = $args->{modified} || 0;
    $self;
}

#------------------------------------------

=method build FIELDS

A fast way to construct a header with many lines.  The FIELDS are
name--content pairs of the header.   A header is created, and each
pair is added.  Doubles are permitted.

=examples

 my $head = Mail::Message::Head->build
  ( From     => 'me@example.com'
  , To       => 'you@anywhere.aq'
  , Received => 'one'
  , Received => 'two'
  );

=cut

sub build(@)
{   my $self = shift;
    my $head = $self->new;
    $head->add(shift, shift) while @_;
    $head;
}

#------------------------------------------

=head2 The Header

=cut

#------------------------------------------

=method isDelayed

Headers may only be partially read, in which case they are called delayed.
This method returns true if some header information still needs to be
read. Returns false if all header data has been read.
Will never trigger completion.

=cut

sub isDelayed { 1 }

#------------------------------------------

=method isMultipart

Returns whether the body of the related message is a multipart body.
May trigger completion.

=cut

sub isMultipart()
{   my $type = shift->get('Content-Type');
    $type && $type->body =~ m[^multipart/]i;
}

#------------------------------------------

=method modified [BOOLEAN]

Sets the modified flag to BOOLEAN.  Without value, the current setting is
returned, but in that case you can better use isModified().
Changing this flag will not trigger header completion.

=examples

 $head->modified(1);
 if($head->modified) { ... }
 if($head->isModified) { ... }

=cut

sub modified(;$)
{   my $self = shift;
    return $self->isModified unless @_;
    $self->{MMH_modified} = shift;
}

#------------------------------------------

=method isModified

Returns whether the header has been modified after being read.

=examples

 if($head->isModified) { ... }

=cut

sub isModified() { shift->{MMH_modified} }

#------------------------------------------

=method isEmpty

Are there any fields defined in the current header?  Be warned that
the header will not be loaded for this: delayed headers will return
true in any case.

=cut

sub isEmpty { scalar keys %{shift->{MMH_fields}} }

#------------------------------------------

=method message [MESSAGE]

Get (after setting) the message where this header belongs to.
This does not trigger completion.

=cut

sub message(;$)
{   my $self = shift;
    if(@_)
    {    $self->{MMH_message} = shift;
         weaken($self->{MMH_message});
    }

    $self->{MMH_message};
}

#------------------------------------------

=head2 Constructing a Header

=cut

#------------------------------------------

sub setField($$) {shift->add(@_)} # compatibility

#------------------------------------------

=head2 Access to the Header

=cut

#------------------------------------------

=method get NAME [,INDEX]

Get the data which is related to the field with the NAME.  The case of the
characters in NAME does not matter.

If there is only one data element defined for the NAME, or if there is an
INDEX specified as the second argument, only the specified element will be
returned. If the field NAME matches more than one header the return value
depends on the context. In LIST context, all values will be returned in
the order they are read. In SCALAR context, only the last value will be
returned.

=examples

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
    my $value = $known->{lc(shift)};
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

=method knownNames

Like names(), but only returns the known header fields, which
may be less than names() for header types which are partial.
names() will trigger completion, where C<knownNames> does not.

=cut

sub knownNames() { keys %{shift->{MMH_fields}} }

#------------------------------------------

=method printUndisclosed [FILEHANDLE]

Like the usual print(), the header lines are printed to the specified
FILEHANDLE, by default the selected filehandle.  In this case, however,
C<Bcc> and C<Resent-Bcc> lines are included.

=cut

#------------------------------------------
# To satisfy overload in static resolving.
    
sub toString() { shift->load->toString }
sub string()   { shift->load->string }

sub string_unless_carp()
{   my $self = shift;
    return $self->toString unless (caller)[0] eq 'Carp';

    (my $class = ref $self) =~ s/^Mail::Message/MM/;
    "$class object";
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method read PARSER

Read the header information of one message into this header structure.  This
method is called by the folder object (some Mail::Box sub-class), which
passes the PARSER as an argument.  Do not call this method yourself!

=cut

sub read($)
{   my ($self, $parser) = @_;

    my @fields = $parser->readHeader;
    @$self{ qw/MMH_begin MMH_end/ } = (shift @fields, shift @fields);

    my $type   = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    $self->addNoRealize($type->new( @$_ ))
        foreach @fields;

    $self;
}

#------------------------------------------

=method orderedFields

Retuns the fields ordered the way they were read or added.

=cut

sub orderedFields() { grep {defined $_} @{shift->{MMH_order}} }

#------------------------------------------

=method addOrderedFields FIELDS

=cut

#  Warning: fields are added in addResentGroup() as well!
sub addOrderedFields(@)
{   my $order = shift->{MMH_order};
    foreach (@_)
    {   push @$order, $_;
        weaken( $order->[-1] );
    }
    @_;
}

#------------------------------------------

=method load

Be sure that the header is loaded.  This returns the loaded header
object.

=cut

sub load($) {shift}

#------------------------------------------

=method fileLocation

Returns the location of the header in the file, as a pair begin and end.  The
begin is the first byte of the header.  The end is the first byte after
the header.

=cut

sub fileLocation()
{   my $self = shift;
    @$self{ qw/MMH_begin MMH_end/ };
}

#------------------------------------------

=method moveLocation DISTANCE

Move the registration of the header in the file.

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMH_begin} -= $dist;
    $self->{MMH_end}   -= $dist;
    $self;
}

#------------------------------------------

=method setNoRealize FIELD

Set a field, but avoid the loading of a possibly partial header as set()
does.  This method does not test the validity of the argument, nor flag the
header as changed.  This does not trigger completion.

=cut

sub setNoRealize($)
{   my ($self, $field) = @_;

    my $known = $self->{MMH_fields};
    my $name  = $field->name;

    $self->addOrderedFields($field);
    $known->{$name} = $field;
    $field;
}

#------------------------------------------

=method addNoRealize FIELD

Add a field, like add() does, but avoid the loading of a possibly partial
header.  This method does not test the validity of the argument, nor flag
the header as changed.  This does not trigger completion.

=cut

sub addNoRealize($)
{   my ($self, $field) = @_;

    my $known = $self->{MMH_fields};
    my $name  = $field->name;

    $self->addOrderedFields($field);

    if(defined $known->{$name})
    {   if(ref $known->{$name} eq 'ARRAY') { push @{$known->{$name}}, $field }
        else { $known->{$name} = [ $known->{$name}, $field ] }
    }
    else
    {   $known->{$name} = $field;
    }

    $field;
}

#------------------------------------------

1;
