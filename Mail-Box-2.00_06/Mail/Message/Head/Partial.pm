
use strict;

package Mail::Message::Head::Partial;

use base 'Mail::Message::Head';

use Object::Realize::Later
    becomes => 'Mail::Message::Head::Complete',
    realize => 'load';

our $VERSION = '2.00_06';

use Carp;
use Date::Parse;

=head1 NAME

 Mail::Message::Head::Partial - Incomplete header information of a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Head::Partial realizes Mail::Message::Head::Complete
 is a Mail::Message::Head              is a Mail::Message::Head
 is a Mail::Reporter                   is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message::Head::Partial $partial = ...;
 $partial->isa('Mail::Message::Head')  # true
 $partial->guessBodySize               # integer or undef
 $partial->isDelayed                   # true

 See Mail::Message::Head

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box-Overview> first.

You decide to use a partial-header when you do not want to store all of
the header-lines.  The C<Received> header lines, for example, can consume
about 20% of the folder-data (so of required memory if you read the message's
header)

Partial headers are created when you specify C<take_header> arguments for
the folder.  See the C<Mail::Box> documentation for information about how
to use the C<take_header> option during instantiation (opening) of a folder.

The message headers are all read from file, but only some selected headers
are stored in memory.

When you access header fields which are not in the partial header -and
the filter indicates that they were left-out on purpose- the whole
header will be parsed (which may consume considerable time, depending on the
type of folder).

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head::Partial> objects:

  MMH add ...                           MR log [LEVEL [,STRINGS]]
  MMH clone [FIELDS]                   MMH message [MESSAGE]
      count NAME                       MMH names
  MMH createFromLine                       new OPTIONS
  MMH createMessageId                  MMH print FILE [,LINE-LENGTH]
   MR errors                            MR report [LEVEL]
      filter [TAKE_HEADERS]             MR reportAll [LEVEL]
      get NAME [,INDEX]                MMH reset NAME, FIELDS
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH set ...
  MMH guessBodySize                    MMH timestamp
  MMH guessTimestamp                    MR trace [LEVEL]
  MMH isDelayed                            usedFilter
  MMH isMultipart                       MR warnings

The extra methods for extension writers:

  MMH load                              MR notImplemented
   MR logPriority LEVEL                MMH read PARSER

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMH = L<Mail::Message::Head>
 MMHC = L<Mail::Message::Head::Complete>

=head1 METHODS

=over 4

=item new OPTIONS

(Class method) Create a header-line container.

 OPTION         DEFINED BY              DEFAULT
 complete_type  Mail::Message::Head     'Mail::Message::Head::Complete'
 field_type     Mail::Message::Head     'Mail::Message::Field'
 filter         Mail::Message::Head::Partial   undef
 log            Mail::Reporter          'WARNINGS'
 message        Mail::Message::Head     undef
 trace          Mail::Reporter          'WARNINGS'

=over 4

=item * filter =E<gt> REGEX

A REGular EXpression which specifies the header-lines which will be taken
from the file which is read.

=back

=cut

my $filter;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{MMHP_filter}  = $filter;
    $self->{MMHP_message} = $args->{message};

    $self;
}

#-------------------------------------------

=item filter [TAKE_HEADERS]

(Class method) This method can be used to specify which fields must be
taken from all the following headers. These header specifications are
packed together in one regular expression which is stored in the header
object. This pattern will be used later to check whether there is a chance
that the real header does have other header fields.

The TAKE_HEADERS argument is a list of patterns or nothing, which
indicates that we don't know if further headers exist.

=cut

sub filter(;@)
{   my $self = shift;

    return $filter = undef unless @_;

    my $take = '^(?:'
             . join( ')|(?:', @_)
             . ')\s*(\:|$)';

    $self->{MMHP_filter} = qr/$take/i;
    $self;
}

#-------------------------------------------

=item get NAME [,INDEX]

Get the information of field with NAME, optionally the specified
INDEXed one.  When the partial header contains this information, it
will be returned immediately, otherwise the head will be loaded from
source, and then the information delived.

For detailes, see the C<get()> method in C<Mail::Message::Head>.

=cut

sub get(;$$)
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

    $self->load->get($name, @_);
}

#-------------------------------------------

=item count NAME

Count the number of appearances of the field with the specified NAME.  When
that field is not contained in the partial header, but may be present in
the complete header, the full header will be loaded first.

=cut

sub count($)
{   my ($self, $name) = @_;

    return $self->load->count($name)
       if !defined $filter || $name !~ $filter;

    my @values = $self->get($name);
    scalar @values;
}

#-------------------------------------------

=item usedFilter

Returns the regular expression which filters the headers for this partial
header storage object.

=cut

# this method is not used by other methods in this package, because it is
# too often needed.  Now we save many many calls.

sub usedFilter() { shift->{MMHP_filter} }

#-------------------------------------------
# Be carefull not to trigger loading: this is not the thoroughness
# we want from this method.

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->SUPER::get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->SUPER::get('Lines');   # 40 chars per lines
    return $1*40 if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#-------------------------------------------
# Be carefull not to trigger loading: this is not the thoroughness
# we want from this method.

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMHP_timestamp} if $self->{MMHP_timestamp};

    my $stamp;
    if(my $date = $self->SUPER::get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach ($self->SUPER::get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MMHP_timestamp} = $stamp;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_06.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
