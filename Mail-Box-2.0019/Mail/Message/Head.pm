use strict;
use warnings;

package Mail::Message::Head;
use base 'Mail::Reporter';

use Mail::Message::Head::Complete;
use Mail::Message::Field;
use Mail::Box::Parser;

use Carp;
use Scalar::Util 'weaken';
use FileHandle;

our $VERSION = 2.00_19;

use overload bool => sub {1};

=head1 NAME

Mail::Message::Head - the header of one message

=head1 CLASS HIERARCHY

 Mail::Message::Head
 is a Mail::Reporter

=head1 SYNOPSIS

 my $head = Mail::Message::Head->new;
 $head->add('From: me@localhost');
 $head->add(From => 'me@localhost');
 $head->add(Mail::Message::Field->new(From => 'me'));
 my Mail::Message::Field $subject = $head->get('subject');
 my Mail::Message::Field @rec = $head->get('received');
 $head->delete('From');

=head1 DESCRIPTION

C<Mail::Message::Head> MIME headers are part of C<Mail::Message> messages,
which are processed by C<Mail::Box> folders.  See C<Mail::Box-Overview>
first.

The header of a MIME message object contains a set of lines, which are
called I<fields> (by default represented by C<Mail::Message::Field>
objects).  Dependent on the situation, the knowledge about the fields can
be in one of three situations, each represented by a sub-class of this
module:

=over 4

=item * C<Mail::Message::Head::Complete>

In this case, it is sure that all knowledge about the header is available.
When you C<get()> information from the header and it is not there, it will
never be there.

=item * C<Mail::Message::Head::Subset>

There is no certainty whether all header lines are known (probably not).  This
may be caused as result of reading a fast index file, as described in
C<Mail::Box::Index>.  The object is automatically transformed
into a C<Mail::Message::Head::Complete> when all header lines must be known.

=item * C<Mail::Message::Head::Delayed>

In this case, there is no single field known.  Access to this header will
always trigger the loading of the full header.

=back

On this page, the general methods which are available on any header are
described.  Read about differences in the sub-class specific pages.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head> objects:

      add ...                              new OPTIONS
      build FIELDS                         nrLines
      count NAME                           print FILEHANDLE
   MR errors                               printUndisclosed FILEHANDLE
      get NAME [,INDEX]                 MR report [LEVEL]
      isDelayed                         MR reportAll [LEVEL]
      isMultipart                          reset NAME, FIELDS
      isResent                             set ...
      knownNames                           size
   MR log [LEVEL [,STRINGS]]               timestamp
      modified [BOOL]                      toString
      names                             MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                              load
      addNoRealize FIELD                MR logPriority LEVEL
      clone [FIELDS]                    MR logSettings
      createFromLine                       message [MESSAGE]
      createMessageId                      moveLocation DISTANCE
      fileLocation                      MR notImplemented
      grepNames [NAMES|ARRAY-OF-N...       read PARSER
      guessBodySize                        setNoRealize FIELD
      guessTimestamp                       wrapLength [CHARS]

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message header object.  The object will store all the
fields of a header.  When you get information from the header, it
will be returned to you as C<Mail::Message::Field> objects, although
the fields may be stored differently internally.

If you try to instantiate a C<Mail::Message::Head>, you will automatically
be upgraded to a C<Mail::Message::Head::Complete> -a full head.

The following options can be specified:

 OPTION       DEFINED BY                DEFAULT
 field_type   Mail::Message::Head       'Mail::Message::Field'
 log          Mail::Reporter            'WARNINGS'
 message      Mail::Message::Head       undef
 modified     Mail::Message::Head       0
 trace        Mail::Reporter            'WARNINGS'
 wrap_length  Mail::Message::Head       72

=over 4

=item * field_type =E<gt> CLASS

The type of objects that all the fields will have.  This must be
an extension of C<Mail::Message::Field>.

=item * message =E<gt> MESSAGE

The MESSAGE where this header belongs to.  Usually, this is not known
at creation of the header, but sometimes it is.  If not, call the
C<message()> method later to set it.

=item * wrap_length =E<gt> INTEGER

Set the desired maximum length of structured header fields to the
specified INTEGER.  If wrap_length is less than 1, wrapping is
disabled.

=back

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

=item build FIELDS

A fast way to construct a header with many lines.  The FIELDS are
name--content pairs of the header.   A header is created, and each
pair is added.  Doubles are permitted.

Example:

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

=item add FIELD

=item add LINE

=item add NAME, BODY [,COMMENT]

Add a field to the header.  If a field is added more than once, all values
are stored in the header, in the order they are added.

The return value of this method is the C<Mail::Message::Field> object
which is created (or was specified).

Examples:

   my $head  = Mail::Message::Head->new;
   $head->add('Subject: hi!');
   $head->add(From => 'me@home');
   my $field = Mail::Message::Field->new('To: you@there');
   $head->add($field);
   my Mail::Message::Field $s = $head->add(Sender => 'I');

=cut

# Triggers completion

sub setField($$) {shift->add(@_)} # compatibility

#------------------------------------------

=item set FIELD

=item set LINE

=item set NAME, BODY [,COMMENT]

The C<set> method is similar to the C<add()> method, and takes the same
options. However, existing values for fields will be removed before a new
value is added.

=cut

# Triggers completion

#------------------------------------------

=item get NAME [,INDEX]

Get the data which is related to the field with the NAME.  The case of the
characters in NAME does not matter.

If there is only one data element defined for the NAME, or if there is an
INDEX specified as the second argument, only the specified element will be
returned. If the field NAME matches more than one header the return value
depends on the context. In LIST context, all values will be returned in
the order they are read. In SCALAR context, only the last value will be
returned.

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

Replace the values in the header fields named by NAME with the values
specified in the list of FIELDS. A single name can correspond to multiple
repeated fields.  If FIELDS is empty, the corresponding NAME fields will
be removed. The location of removed fields in the header order will be
remembered. Fields with the same name which are added later will appear at
the remembered position.

Examples:

    # reduce number of 'Received' lines to last 5)
    my @received = $head->get('Received');
    $head->reset('Received', @received[-5..-1]) if @received > 5;

=cut

# Triggers completion
 
#------------------------------------------

=item knownNames

=item names

Returns a full ordered list of known field names, as defined in the
header.  Fields which were C<reset()> to be empty will still be
listed here.  C<knownNames> only returns the known header fields, which
may be less than C<names> for header types which are partial.

=cut

sub knownNames() { @{shift->{MMH_order}} }

# 'names' triggers completion

#------------------------------------------

=item isDelayed

Headers may only be partially read, in which case they are called delayed.
This method returns true if some header information still needs to be
read. Returns false if all header data has been read.

=cut

sub isDelayed { 1 }

#------------------------------------------

=item isMultipart

=cut

sub isMultipart()
{   my $type = shift->get('Content-Type');
    $type && $type->body =~ m[^multipart/]i;
}

#------------------------------------------

=item print FILEHANDLE

=item printUndisclosed FILEHANDLE

Print the header to the specified FILEHANDLE.  In the former case,
C<Bcc> and C<Resent-Bcc> lines are included, in the latter case not.

Examples:

    $head->print(\*STDOUT);

    my $fh = FileHandle->new(...);
    $head->print($fh);

=cut

# Triggers completion for headers which do not implement a different
# solution.

#------------------------------------------

=item toString

Returns the whole header as one scalar (in scalar context) or list
of lines (list context).

=cut

# Triggers completion.

#------------------------------------------

=item timestamp

Will return a good timestamp, with as little guessing as possible.  This
will trigger reading of the header (if not already read).

=cut

# Triggers completion

#------------------------------------------

=item nrLines

Return the number of lines needed to display this header (including
the trailing newline)

=cut

# Triggers completion

#------------------------------------------

=item size

Return the number of bytes needed to display this header (including
the trailing newline)

=cut

# Triggers completion

#------------------------------------------

=item modified [BOOL]

Returns whether the header has been modified after being read, optionally
after setting that status first.

Examples:

 if($head->modified) { ... }
 $head->modified(1);

=cut

sub modified(;$)
{   my $self = shift;
    @_ ? $self->{MMH_modified} = shift : $self->{MMH_modified};
}

#------------------------------------------

=item isResent

Return whether this message is the result of a bounce.  The bounce
will produced lines which start with C<Resent->, line C<Resent-To>
which has preference over C<To> as destination for the message.

=cut

sub isResent() { shift->get('resent-message-id') }

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item read PARSER

Read the header information of one message into this header structure.  This
method is called by the folder object (some C<Mail::Box> sub-class), which
passes the PARSER as an argument.  Do not call this method yourself!

=cut

sub read($)
{   my ($self, $parser) = @_;

    my $pairs     = [ $parser->readHeader($self->{MMH_wrap_length}) ];
    @$self{ qw/MMH_begin MMH_end/ } = splice @$pairs, 0, 2;
    return unless @$pairs;

    $parser->defaultParserType(ref $parser);

    my $known     = $self->{MMH_fields};
    my $wrap      = $self->{MMH_wrap_length};
    my $fieldtype = $self->{MMH_field_type} || 'Mail::Message::Field';

    while(@$pairs)
    {   my ($name, $body) = (shift @$pairs, shift @$pairs);
        my $field = $fieldtype->new($name, $body);
        $field->setWrapLength($wrap);
        $name     = lc $name;

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

=item clone [FIELDS]

Make a copy of the header, optionally limited only to the header lines
specified by FIELDS.  The lines which are taken must start with one of the
list.  If no list is specified, all will be taken.

Example:

   my $newhead = $head->clone('Subject', 'Received');

=cut

# Triggers completion.

#------------------------------------------

=item grepNames [NAMES|ARRAY-OF-NAMES]

Filter from all header names the names which start will any of the
specified list.  When no names are specified, all names will be returned.
The list is ordered as they where read from file, or added later.

The NAMES are regular expressions, and will all be matched case insensitive
and attached to the front of the string only.

Examples:

   print $head->grepNames();         # same as $head->names
   print $head->grepNames('X-', 'Subject', ');
   print $head->grepNames('To\b');   # will only select To

=cut

sub grepNames(@)
{   my $self = shift;
    return $self->names unless @_;

    my @take;
    push @take, (ref $_ ? @$_ : $_) foreach @_;

    # I love this tric:
    local $"   = ')|(?:';
    my $take   = qr/^(?:(?:@_))/i;

    grep {$_ =~ $take} $self->names;
}

#------------------------------------------

=item guessBodySize

Try to estimate the size of the body of this message, but without parsing
the header or body.  The result might be C<undef> or a few percent of
the real size.  It may even be very far of the real value, that's why
this is a guess.

=cut

# Triggers completion

#------------------------------------------

=item guessTimestamp

Try to get a good guess about the time this message was transmitted.  This
moment may be somewhere from start of transmission by the sender till
receipt.  It may return C<undef>.

=cut

# Triggers completion, but is usually overruled by other headers.

#------------------------------------------

=item message [MESSAGE]

Get (after setting) the message where this header belongs to.

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

=item load

Be sure that the header is loaded.  This returns the loaded header
object.

=cut

sub load($) {shift}

#------------------------------------------

=item fileLocation

Returns the location of the header in the file, as a pair begin and end.  The
begin is the first byte of the header.  The end is the first byte after
the header.

=cut

sub fileLocation()
{   my $self = shift;
    @$self{ qw/MMH_begin MMH_end/ };
}

#------------------------------------------

=item moveLocation DISTANCE

Move the registration of the header in the file.

=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MMH_begin} -= $dist;
    $self->{MMH_end}   -= $dist;
    $self;
}

#------------------------------------------

=item createFromLine

For some mail-folder types separate messages by a line starting with
'C<From >'.  If a message is moved to such folder from a folder-type
which does not support these separators, this method is called to produce
one.

=cut

# Triggers completion

#------------------------------------------

=item createMessageId

Creates a message-id for this message.  This method will be run when
a new message is created, or a message is discovered without the
message-id header field.  Message-ids are required for detection of
message-threads.

=cut

my $unique_id = time;

sub createMessageId() { '<mailbox-'.$unique_id++.'>' }

#------------------------------------------

=item wrapLength [CHARS]

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

=item setNoRealize FIELD

Set a field, but avoid the loading of a possibly partial header.  This
method does not test the validity of the argument, nor flag the header
as changed.

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

=item addNoRealize FIELD

Add a field, but avoid the loading of a possibly partial header.  This
method does not test the validity of the argument, nor flag the header
as changed.

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

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_19.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
