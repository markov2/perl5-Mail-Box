
use strict;

package Mail::Message::Head::Subset;

use base 'Mail::Message::Head';

use Object::Realize::Later
    becomes => 'Mail::Message::Head::Complete',
    realize => 'load';

our $VERSION = '2.00_06';

use Carp;
use Date::Parse;

=head1 NAME

 Mail::Message::Head::Subset - subset of header information of a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Head::Subset realizes Mail::Message::Head::Complete
 is a Mail::Message::Head             is a Mail::Message::Head
 is a Mail::Reporter                  is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message::Head::Subset $subset = ...;
 $subset->isa('Mail::Message::Head')  # true
 $subset->guessBodySize               # integer or undef
 $subset->isDelayed                   # true

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box-Overview> first.

Some types of folders contain an index file which lists a few lines of
information per messages.  Especially when it is costly to read header lines,
the index speeds-up access considerably.  For instance, the subjects of
all messages are often wanted, but waiting for a thousand messages of the
folder to be read may imply a thousand network reads (IMAP) or file
openings (MH)

When you access header fields which are not in the header subset, the whole
header has to be parsed (which may consume considerable time, depending on
the type of folder).

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head::Subset> objects:

  MMH add ...                           MR log [LEVEL [,STRINGS]]
  MMH clone [FIELDS]                   MMH message [MESSAGE]
      count NAME                       MMH names
  MMH createFromLine                       new OPTIONS
  MMH createMessageId                  MMH print FILE [,LINE-LENGTH]
   MR errors                            MR report [LEVEL]
      get NAME [,INDEX]                 MR reportAll [LEVEL]
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH reset NAME, FIELDS
  MMH guessBodySize                    MMH set ...
  MMH guessTimestamp                   MMH timestamp
  MMH isDelayed                         MR trace [LEVEL]
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

#-------------------------------------------

=item new OPTIONS

 OPTION         DEFINED BY           DEFAULT
 complete_type  Mail::Message::Head  'Mail::Message::Head::Complete'
 field_type     Mail::Message::Head  'Mail::Message::Field'
 log            Mail::Reporter       'WARNINGS'
 message        Mail::Message::Head  undef
 trace          Mail::Reporter       'WARNINGS'

No options specific to a C<Mail::Message::Head::Subset>

=cut

#-------------------------------------------

=item get NAME [,INDEX]

Get the value(s) of the field with NAME, or only the one value on
the specified INDEX.  If the field with the specified name is
not (yet) known, the full header will be loaded first.

See C<Mail::Message::Head> for more details.

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

    $self->load->get(@_);
}

#-------------------------------------------

=item count NAME

Count the number of appearances of the field with the specified NAME
in the header.  If the name is not (yet) known, the header will be
loaded first.

=cut

sub count($)
{   my ($self, $name) = @_;

    my @values = $self->get($name);

    return $self->load->count($name)
       unless @values;

    scalar @values;
}

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
    return $self->{MMHS_timestamp} if $self->{MMHS_timestamp};

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

    $self->{MMHS_timestamp} = $stamp;
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