use strict;
use warnings;

package Mail::Message::Body::String;
use base 'Mail::Message::Body';

our $VERSION = '2.00_05';

use Carp;
use IO::Scalar;

=head1 NAME

 Mail::Message::Body::String - body of a Mail::Message stored as single string

=head1 CLASS HIERARCHY

 Mail::Message::Body::String
 is a Mail::Message::Body
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This documentation only describes the
extensions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
documentation you will find the description of extra functionality you have
when a message is stored as a single scalar.  

Storing a whole message in one string is only a smart choice when the content
is small or encoded. Even when stored as a scalar, you can still treat the
body as if the data is stored in lines or an external file, but this will be
slower.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::String> objects:

  MMB clone                            MMB nrLines
  MMB data FILE | LIST-OF-LINES |...   MMB print [FILE]
   MR errors                           MMB read PARSER [,CHARS [,LINES]]
  MMB file                             MMB reply OPTIONS
  MMB isDelayed                         MR report [LEVEL]
  MMB isMultipart                       MR reportAll [LEVEL]
  MMB lines                            MMB size
   MR log [LEVEL [,STRINGS]]           MMB string
  MMB message [MESSAGE]                MMB stripSignature OPTIONS
  MMB new OPTIONS                       MR trace [LEVEL]
   MR new OPTIONS                       MR warnings

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
# The scalar is stored as reference to avoid a copy during creation of
# a string object.

sub _data_from_file(@_)
{   my ($self, $fh) = @_;
    my $data;

    if(ref $fh eq 'GLOB')
    {   local $/ = undef;
        $data = <$fh>;
    }
    else
    {   $data = join '', $fh->getlines;
    }

    $self->{MMBS_scalar} = $data;
}

sub _data_from_lines(@_)
{   my ($self, $lines) = @_;
    my $ref;

    $self->{MMBS_nrlines} = @$lines unless @$lines==1;
    $self->{MMBS_scalar}  = @$lines==1 ? shift @$lines : join('', @$lines);
}

#------------------------------------------

sub clone()
{   my $self = shift;
    ref($self)->new(data => $self->string);
}

#------------------------------------------

sub data(@)
{   my $self = shift;
    delete $self->{MMBS_nrlines};
    $self->SUPER::data(@_);
}

#------------------------------------------

sub string() { shift->{MMBS_scalar} }

#------------------------------------------

sub lines()
{   my @lines = split /(?<=\n)/, shift->{MMBS_scalar};
    wantarray ? @lines : \@lines;
}

#------------------------------------------
# Only compute it once, if needed.  The scalar contains lines, so will
# have a \n even at the end.

sub nrLines()
{   my $self = shift;
    return $self->{MMBS_nrlines} if exists $self->{MMBS_nrlines};

    my $nrlines = 0;
    for($self->{MMBS_scalar})
    {   $nrlines++ while /\n/g;
    }

    $self->{MMBS_nrlines} = $nrlines;
}


sub size() { length shift->{MMBS_scalar} }

#------------------------------------------

sub file() { IO::Scalar->new(shift->{MMBS_scalar}) }

#------------------------------------------

sub read($;@)
{   my ($self, $parser) = (shift, shift);
    @$self{ qw/MMB_where MMBS_scalar/ } = $parser->bodyAsString(@_);
    $self;
}

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $fh   = shift || \*STDOUT;
    $fh->print($self->{MMBS_scalar});
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
