use strict;
use warnings;

package Mail::Message::Body::Lines;
use base 'Mail::Message::Body';

use Mail::Box::Parser;
use IO::Lines;

use Carp;

=chapter NAME

Mail::Message::Body::Lines - body of a Mail::Message stored as array of lines

=chapter SYNOPSIS

 See M<Mail::Message::Body>

=chapter DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
documentation you find the description of extra functionality you have
when a message is stored in an array of lines.

Storing a whole message as an array of lines is useful when the data is not
encoded, and you want to process it on a line-by-line basis (a common practice
for inspecting message bodies).

=chapter METHODS

=c_method new %options

=error Unable to read file $filename for message body lines: $!

A M<Mail::Message::Body::Lines> object is to be created from a named file,
but it is impossible to read that file to retrieve the lines within.

=cut

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    local *IN;

    unless(open IN, '<', $filename)
    {   $self->log(ERROR =>
             "Unable to read file $filename for message body lines: $!");
        return;
    }

    $self->{MMBL_array} = [ <IN> ];

    close IN;
    $self;
}

sub _data_from_filehandle(@)
{   my ($self, $fh) = @_;
    $self->{MMBL_array} =
       ref $fh eq 'Mail::Box::FastScalar' ? $fh->getlines : [ $fh->getlines ];
    $self
}

sub _data_from_glob(@)
{   my ($self, $fh) = @_;
    $self->{MMBL_array} = [ <$fh> ];
    $self;
}

sub _data_from_lines(@)
{   my ($self, $lines)  = @_;
    $lines = [ split /^/, $lines->[0] ]    # body passed in one string.
        if @$lines==1;

    $self->{MMBL_array} = $lines;
    $self;
}

#------------------------------------------

sub clone()
{   my $self  = shift;
    ref($self)->new(data => [ $self->lines ], based_on => $self);
}

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

sub string() { join '', @{shift->{MMBL_array}} }

#------------------------------------------

sub lines() { wantarray ? @{shift->{MMBL_array}} : shift->{MMBL_array} }

#------------------------------------------

sub file() { IO::Lines->new(shift->{MMBL_array}) }

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    if(ref $fh eq 'GLOB') { print $fh @{$self->{MMBL_array}}   }
    else                  { $fh->print(@{$self->{MMBL_array}}) }
    $self;
}

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    my ($begin, $end, $lines) = $parser->bodyAsList(@_);
    $lines or return undef;

    $self->fileLocation($begin, $end);
    $self->{MMBL_array} = $lines;
    $self;
}

#------------------------------------------

sub endsOnNewline()
{   my $last = shift->{MMBL_array}[-1];
    !defined $last || $last =~ m/\n$/;
}

#------------------------------------------

1;
