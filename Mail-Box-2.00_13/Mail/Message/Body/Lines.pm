use strict;
use warnings;

package Mail::Message::Body::Lines;
use base 'Mail::Message::Body';

use Mail::Box::Parser;
use IO::Lines;

our $VERSION = '2.00_13';

use Carp;

=head1 NAME

 Mail::Message::Body::Lines - Body of a Mail::Message stored as array of lines

=head1 CLASS HIERARCHY

 Mail::Message::Body::Lines
 is a Mail::Message::Body + ::Construct + ::Encode
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extensions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
documentation you find the description of extra functionality you have
when a message is stored in an array of lines.

Storing a whole message as an array of lines is useful when the data is not
encoded, and you want to process it on a line-by-line basis (a common practice
for inspecting message bodies).

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Lines> objects:

 MMBC attach MESSAGES                  MMB message [MESSAGE]
  MMB checked [BOOLEAN]                MMB modified [BOOL]
 MMBC concatenate BODY [,BODY, .....       new OPTIONS
  MMB decoded OPTIONS                  MMB nrLines
  MMB disposition [STRING|FIELD]           print [FILE]
 MMBE encode OPTIONS                   MMB reply OPTIONS
   MR errors                            MR report [LEVEL]
  MMB file                              MR reportAll [LEVEL]
 MMBC foreachLine CODE                 MMB size
  MMB isBinary                         MMB string
  MMB isDelayed                       MMBC stripSignature OPTIONS
  MMB isMultipart                       MR trace [LEVEL]
  MMB lines                            MMB transferEncoding
   MR log [LEVEL [,STRINGS]]           MMB type

The extra methods for extension writers:

   MR AUTOLOAD                         MMB load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
  MMB clone                             MR notImplemented
 MMBE getTransferEncHandler TYPE       MMB read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction              MMB start

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>
 MMBC = L<Mail::Message::Body::Construct>
 MMBE = L<Mail::Message::Body::Encode>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION    DESCRIBED IN                  DEFAULT
 data      Mail::Message::Body           undef
 log       Mail::Reporter                'WARNINGS'
 message   Mail::Message::Body           undef
 modified  Mail::Message::Body           0
 trace     Mail::Reporter                'WARNINGS'

=cut

#------------------------------------------

sub string() { join '', @{shift->{MMBL_array}} }

#------------------------------------------

sub lines()
{   wantarray ? @{shift->{MMBL_array}}   # all lines
      : [ @{shift->{MMBL_array}} ]       # new ref array to avoid accidental
}                                        #   destruction of body itself.

#------------------------------------------

sub file() { IO::Lines->new(shift->{MMBL_array}) }

#------------------------------------------

sub nrLines() { scalar @{shift->{MMBL_array}} }

#------------------------------------------
# Optimized to be computed only once.

sub size()
{   my $self = shift;
    return $self->{MMBL_size} if exists $self->{MMBL_size};

    my $size = 0;
    $size += length $_ foreach @{$self->{MMBL_array}};
    $self->{MMBL_size} = $size;
}

#------------------------------------------

=item print [FILE]

=cut

sub print(;$)
{   my $self = shift;
    my $fh   = shift || \*STDOUT;
    $fh->print(@{$self->{MMBL_array}});
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub data(@)
{   my $self = shift;
    delete $self->{MMBL_size};
    $self->SUPER::data(@_);
}

sub _data_from_file(@_)
{   my ($self, $fh) = @_;
    my @data = ref $fh eq 'GLOB' ? <$fh> : $fh->getlines;
    $self->{MMBL_array} = \@data;
}

sub _data_from_lines(@_)
{   my ($self, $lines)  = @_;
    $lines = [ split /(?<=\n)/, $lines->[0] ] # body passed in one string.
        if @$lines==1;

    $self->{MMBL_array} = $lines;
}

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    $self->{MMBL_array} = [ $parser->bodyAsList(@_) ];
    $self->{MMB_where} = shift @{$self->{MMBL_array}};
    $self;
}

#------------------------------------------

sub clone()
{   my $self  = shift;
    ref($self)->new(data => [ $self->lines ] );
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_13.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
