use strict;
use warnings;

package Mail::Message::Body::Lines;
use base 'Mail::Message::Body';

use Mail::Box::Parser;

our $VERSION = '2.00_05';

use Carp;

=head1 NAME

Mail::Message::Body::Lines - Body of a Mail::Message stored as array of lines

=head1 CLASS HIERARCHY

 Mail::Message::Body::Lines
 is a Mail::Message::Body
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

  MMB clone                            MMB nrLines
  MMB data FILE | LIST-OF-LINES |...       print [FILE]
   MR errors                           MMB print [FILE]
  MMB file                             MMB read PARSER [,CHARS [,LINES]]
  MMB isDelayed                        MMB reply OPTIONS
  MMB isMultipart                       MR report [LEVEL]
  MMB lines                             MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]           MMB size
  MMB message [MESSAGE]                MMB string
  MMB new OPTIONS                      MMB stripSignature OPTIONS
   MR new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

    MR = L<Mail::Reporter>
   MMB = L<Mail::Message::Body>


=head1 METHODS

=over 4

=cut

#------------------------------------------

sub clone()
{   my $self  = shift;
    ref($self)->new(data => [ $self->lines ] );
}

#------------------------------------------

sub data(@)
{   my $self = shift;
    delete $self->{MMBL_size};
    $self->SUPER::data(@_);
}

sub _data_from_file(@_)
{   my ($self, $fh) = @_;
    my @data;

    if(ref $fh eq 'GLOB')
    {   @data = <$fh>;
    }
    else
    {   @data = $fh->getlines;
    }

    $self->{MMBL_array} = \@data;
}

sub _data_from_lines(@_)
{   my ($self, $lines)  = @_;
    $lines = [ split /(?<=\n)/, $lines->[0] ] # body passed in one string.
        if @$lines==1;

    $self->{MMBL_array} = $lines;
}

#------------------------------------------

sub string() { join '', @{shift->{MMBL_array}} }

#------------------------------------------

sub lines()
{   wantarray ? @{shift->{MMBL_array}}   # all lines
      : [ @{shift->{MMBL_array}} ]       # new ref array to avoid accidental
}                                        #   destruction of body itself.

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

sub file() { IO::Lines->new(shift->{MMBL_array}) }

#------------------------------------------

sub read($;@)
{   my ($self, $parser) = (shift, shift);
    $self->{MMBL_array} = [ $parser->bodyAsList(@_) ];
    $self->{MMB_where} = shift @{$self->{MMBL_array}};
    $self;
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

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_05.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
