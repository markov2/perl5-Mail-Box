
use strict;

package Mail::Message::Head::Partial;
use base 'Mail::Message::Head';

our $VERSION = '2.00_01';

=head1 NAME

Mail::Message::Head::Partial - Incomplete header information of a Mail::Message

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box::Manager> first.

The partial message-header object contains a subset of the actual headers
of a message.  They can appear for two reasons:

=over 4

=item * when you specify C<take_header> arguments for the folder

See C<Mail::Box> about how to use that option during instantiation
-opening- of a folder.  The message-headers are all read, but only
some selected headers are kept mainly to save memory.

=item * when the folder contains a fast index

Some kinds of folders have a fast indexing facility.  For instance, C<emh>
folders maintain an index with some header-lines plus the first body-line
of each message.  Also C<IMAP> has such features.

=back

When you access header-fields which are not in the list which is captured
in this partial-header, the whole header has to be parsed (which may
consume considerable time, depending on the type of folder).

=head2 METHODS

=over 4

=item new

(Class method) Create a header-line container.
ARGS.

=cut

my $filter;

sub new(@) { (bless {}, shift)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{MMHP_filter}  = $filter;

    $self->{MMHP_message} = $args->{message}
       or croak __PACKAGE__." needs to know the message.\n";

    $self;
}

#-------------------------------------------

=item filter [TAKE_HEADERS]

(Class method) Set which fields must be taken from all the following
headers.  These headers are packed together in one regular expression
which is stored in the headers, to be able to check later whether there
is a chance that the real header does have other headers.

The TAKE_HEADERS argument is a list of patterns or nothing, which means
we don't know.

=cut

sub filter(;@)
{   my $self = shift

    return $filter = undef unless @_;

    $take   = '^(?:'
            . join( ')|(?:', @_)
            . ')\s*(\:|$)';

    $filter = qr/$take/i;
    $self;
}

#-------------------------------------------

=cut

sub get($;$)
{   my $self = shift;

    if(wantarray)
    {   my @values = $self->SUPER::get(@_);
        return @values if @values;
    }
    else
    {   my $value  = $self->SUPER::get(@_);
        return $value  if $value;
    }

    my $filter = $self->{MMHP_filter};
    my $name   = shift;

    return () if $filter && $name =~ $filter;

    $self->message->load_head->get($name, @_);
}

#-------------------------------------------

sub add(@_)   { $self->message->load_head->add(@_)   }
sub set(@_)   { $self->message->load_head->set(@_)   }
sub reset(@_) { $self->message->load_head->reset(@_) }
sub names(@_) { $self->message->load_head->names(@_) }
sub print(@_) { $self->message->load_head->print(@_) }

#-------------------------------------------
# Count can only be done if the field is known.

sub count($)
{   my ($self, $name) = @_;

    return $self->message->load_head->count($name)
       if !defined $filter || $arg !~ $filter;

    my @values = $self->get($name);
    scalar @values;
}

#-------------------------------------------

sub isDelayed() { 1 }

#-------------------------------------------

=item message

Get the message to which this header belongs.

=cut

sub message(;$) { $self->{MMHP_message} }

#-------------------------------------------

=item filter

Returns the regular expression which filters the headers for this partial
header-storage object.

=cut

# this method is not used by other methods in this package, because it is
# too often needed.  Now we save many many calls.

sub filter() { shift->{MMHP_filter} }

#-------------------------------------------


#-------------------------------------------

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_01

=cut

1;
