use strict;
use warnings;

package Mail::Message::Body::Lines;
use base 'Mail::Message::Body';

use Mail::Box::Parser;

our $VERSION = '2.00_08';

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
   MR errors                           MMB reply OPTIONS
  MMB file                              MR report [LEVEL]
  MMB isDelayed                         MR reportAll [LEVEL]
  MMB isMultipart                      MMB size
  MMB lines                            MMB string
   MR log [LEVEL [,STRINGS]]           MMB stripSignature OPTIONS
  MMB message [MESSAGE]                 MR trace [LEVEL]
  MMB new OPTIONS                       MR warnings

The extra methods for extension writers:

  MMB load                              MR notImplemented
   MR logPriority LEVEL                MMB read PARSER, HEAD, BODYTYPE...
   MR logSettings                      MMB start

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
#warn "Body has ", scalar @{$self->{MMBL_array}}, " lines.";
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

sub read($$$;@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
#warn "Start reading body.\n";
    $self->{MMBL_array} = [ $parser->bodyAsList(@_) ];
#warn "End reading body.\n";
    $self->{MMB_where} = shift @{$self->{MMBL_array}};
#warn "Shift done.\n";
    $self;
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

This code is beta, version 2.00_08.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
