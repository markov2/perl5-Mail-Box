use strict;
use warnings;

package Mail::Message::Body::String;
use base 'Mail::Message::Body';

our $VERSION = 2.011;

use Carp;
use IO::Scalar;

=head1 NAME

Mail::Message::Body::String - body of a Mail::Message stored as single string

=head1 CLASS HIERARCHY

 Mail::Message::Body::String
 is a Mail::Message::Body + ::Construct + ::Encode
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

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Body> (MMB), L<Mail::Message::Body::Construct> (MMBC), L<Mail::Message::Body::Encode> (MMBE).

The general methods for C<Mail::Message::Body::String> objects:

 MMBC attach MESSAGES, OPTIONS          MR log [LEVEL [,STRINGS]]
 MMBE check                            MMB message [MESSAGE]
  MMB checked [BOOLEAN]                MMB mimeType
 MMBC concatenate COMPONENTS           MMB modified [BOOL]
  MMB decoded OPTIONS                      new OPTIONS
  MMB disposition [STRING|FIELD]       MMB nrLines
 MMBE encode OPTIONS                   MMB print [FILE]
 MMBE encoded                          MMB reply OPTIONS
  MMB eol ['CR'|'LF'|'CRLF'|'NATI...    MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MMB file                             MMB size
 MMBC foreachLine CODE                 MMB string
 MMBE isBinary                        MMBC stripSignature OPTIONS
  MMB isDelayed                         MR trace [LEVEL]
  MMB isMultipart                      MMB transferEncoding [STRING|FI...
  MMB lines                            MMB type

The extra methods for extension writers:

   MR AUTOLOAD                         MMB load
   MR DESTROY                           MR logPriority LEVEL
 MMBE addTransferEncHandler NAME,...    MR logSettings
  MMB clone                            MMB moveLocation [DISTANCE]
  MMB fileLocation [BEGIN,END]          MR notImplemented
 MMBE getTransferEncHandler TYPE       MMB read PARSER, HEAD, BODYTYPE...
   MR inGlobalDestruction             MMBE unify BODY

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
    return $self->{MMBS_nrlines} if defined $self->{MMBS_nrlines};

    my $nrlines = 0;
    for($self->{MMBS_scalar})
    {   $nrlines++ while /\n/g;
    }

    $self->{MMBS_nrlines} = $nrlines;
}


sub size()
{   my $self = shift;

    for($self->{MMBS_scalar})
    {   return (length) + ( $self->eol eq 'CRLF' ? tr/\n/\n/ : 0);
    }
}

#------------------------------------------

sub file() { IO::Scalar->new(shift->{MMBS_scalar}) }

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    $fh->print($self->{MMBS_scalar});
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------
# The scalar is stored as reference to avoid a copy during creation of
# a string object.

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    delete $self->{MMBS_nrlines};
    unless(open IN, '<', $filename)
    {   $self->log(ERROR => "Unable to read file $filename: $!");
        return;
    }

    my @lines = <IN>;
    close IN;

    $self->{MMBS_nrlines} = @lines;
    $self->{MMBS_scalar}  = join '', @lines;
    $self;
}

sub _data_from_filehandle(@)
{   my ($self, $fh) = @_;
    my @lines = $fh->getlines;
    $self->{MMBS_nrlines} = @lines;
    $self->{MMBS_scalar}  = join '', @lines;
    $self;
}

sub _data_from_glob(@)
{   my ($self, $fh) = @_;
    my @lines = <$fh>;
    $self->{MMBS_nrlines} = @lines;
    $self->{MMBS_scalar}  = join '', @lines;
    $self;
}

sub _data_from_lines(@)
{   my ($self, $lines) = @_;
    $self->{MMBS_nrlines} = @$lines unless @$lines==1;
    $self->{MMBS_scalar}  = @$lines==1 ? shift @$lines : join('', @$lines);
    $self;
}

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    delete $self->{MMBS_nrlines};

    (my $begin, my $end, $self->{MMBS_scalar}) = $parser->bodyAsString(@_);
    $self->fileLocation($begin, $end);

    $self;
}

#------------------------------------------

sub clone()
{   my $self = shift;
    ref($self)->new(data => $self->string);
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

This code is beta, version 2.011.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
