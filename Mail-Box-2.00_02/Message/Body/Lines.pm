use strict;
use warnings;

package Mail::Message::Body::Lines;
use base 'Mail::Message::Body';

use Mail::Box::Parser;

our $VERSION = '2.00_02';

use Carp;

=head1 NAME

Mail::Message::Body::Lines - Body of a Mail::Message stored as array of lines

=head1 SYNOPSIS

   my $body  = $msg->body;
   my $text  = $body->string;
   my @text  = $body->lines;
   my FileHandle $file = $body->file;
   $body->print(\*FILE);

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extentions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message is stored in an array of lines.

Storing a whole message as an array of lines is useful when the data
is not encoded, and you want to process it on line basis (common
practice for inspecting message bodies).

=head1 GENERAL METHODS

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
    $self->{MMBL_array} = $lines;
}

#------------------------------------------

sub string() { join '', @{shift->{MMBL_array}} }

#------------------------------------------

sub lines() { wantarray ? @{shift->{MMBL_array}} : shift->{MMBL_array} }

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

=item read FILE [,LENGTH]

Read the body from the FILE. The implementation of this method will
differ from body-type to body-type.  Read the dedicated man-pages for
the specifics of each reading.

The LENGTH is the estimated number of bytes in the file, of C<undef>
which this is not known.

=cut

sub read($)
{
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

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 1.318, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Message::Body>
L<Mail::Box::Manager>

=cut

1;
