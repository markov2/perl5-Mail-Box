use strict;
use warnings;

package Mail::Message::Head;
use base 'Mail::Reporter';

use Mail::Message::Head::Complete;
use Mail::Message::Field::Fast;
use Mail::Box::Parser;

use Carp;
use Scalar::Util 'weaken';
use FileHandle;

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

=method new OPTIONS

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

=option  wrap_length INTEGER
=default wrap_length 72

Set the desired maximum length of structured header fields to the
specified INTEGER.  If wrap_length is less than 1, wrapping is
disabled.

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

    if(defined $args->{message})
    {   $self->{MMH_message} = $args->{message};
        weaken($self->{MMH_message});
    }

    $self->{MMH_wrap_length} = $args->{wrap_length}
        ? ($args->{wrap_length} > 0 ? $args->{wrap_length} : 0)
        : 72;

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
    $type && $type->body =~ m[^(multipart/)|(message/rfc822)]i;
}

#------------------------------------------

=method modified [BOOLEAN]

Returns whether the header has been modified after being read, optionally
after setting that status first.
This will not trigger completion.

=examples

 if($head->modified) { ... }
 $head->modified(1);

=cut

sub modified(;$)
{   my $self = shift;
    @_ ? $self->{MMH_modified} = shift : $self->{MMH_modified};
}

#------------------------------------------

=method isResent

Return whether this message is the result of a bounce.  The bounce
will produced lines which start with C<Resent->, line C<Resent-To>
which has preference over C<To> as destination for the message.
This may trigger completion.

=cut

sub isResent() { defined shift->get('resent-message-id') }

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

=method knownNames

Like names(), but only returns the known header fields, which
may be less than names() for header types which are partial.
Will never trigger completion.

=cut

sub knownNames() { @{shift->{MMH_order}} }

#------------------------------------------

=method printUndisclosed [FILEHANDLE]

Like the usual print(), the header lines are printed to the specified
FILEHANDLE, by default the selected filehandle.  In this case, however,
C<Bcc> and C<Resent-Bcc> lines are included.

=cut

#------------------------------------------
# To satisfy overload in static resolving.
    
sub toString() { shift->load->toString }

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

    my @fields    = $parser->readHeader($self->{MMH_wrap_length});
    @$self{ qw/MMH_begin MMH_end/ } = (shift @fields, shift @fields);

    $parser->defaultParserType(ref $parser);

    my $known     = $self->{MMH_fields};
    my $fieldtype = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    foreach (@fields)
    {   my $field = $fieldtype->newNoCheck( @$_ );
        my $name  = $field->name;

        push @{$self->{MMH_order}}, $name
            unless exists $known->{$name};

        if(defined $known->{$name})
        {   if(ref $known->{$name} eq 'ARRAY')
                 { push @{$known->{$name}}, $field }
            else { $known->{$name} = [ $known->{$name}, $field ] }
        }
        else
        {   $known->{$name} = $field;
        }
    }

    $self;
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

sub createMessageId()
{  shift->log(INTERNAL =>
       "You didn't check well enough for a msg-id: header should be realized.");
}

#------------------------------------------

=method wrapLength [CHARS]

Returns the soft upper limit length of header lines, optionally after
setting it to CHARS first.

=cut

sub wrapLength(;$)
{   my $self = shift;
    return $self->{MMH_wrap_length} unless @_;

    my $wrap = shift;
    return $wrap if $wrap==$self->{MMH_wrap_length};

    foreach my $name ($self->names)
    {   $_->setWrapLength($wrap) foreach $self->get($name);
    }

    $self->{MMH_wrap_length} = $wrap;
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

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

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

#------------------------------------------

1;
