use strict;
use warnings;

package Mail::Message::Body::String;
use base 'Mail::Message::Body';

use Carp;
use IO::Scalar;

=head1 NAME

Mail::Message::Body::String - body of a Mail::Message stored as single string

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
documentation you will find the description of extra functionality you have
when a message is stored as a single scalar.  

Storing a whole message in one string is only a smart choice when the content
is small or encoded. Even when stored as a scalar, you can still treat the
body as if the data is stored in lines or an external file, but this will be
slower.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=c_method new OPTIONS

=error Unable to read file $filename for message body scalar: $!

A Mail::Message::Body::Scalar object is to be created from a named file, but
it is impossible to read that file to retrieve the lines within.

=cut

#------------------------------------------
# The scalar is stored as reference to avoid a copy during creation of
# a string object.

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    delete $self->{MMBS_nrlines};

    local *IN;
    unless(open IN, '<', $filename)
    {   $self->log(ERROR =>
            "Unable to read file $filename for message body scalar: $!");
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

=head2 The Body

=cut

#------------------------------------------

sub clone()
{   my $self = shift;
    ref($self)->new(data => $self->string, based_on => $self);
}

#------------------------------------------

=head2 About the Payload

=cut

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

#------------------------------------------

sub size() { length shift->{MMBS_scalar} }

#------------------------------------------

=head2 Access to the Payload

=cut

#------------------------------------------

sub string() { shift->{MMBS_scalar} }

#------------------------------------------

sub lines()
{   my @lines = split /^/, shift->{MMBS_scalar};
    wantarray ? @lines : \@lines;
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

sub printEscapedFrom($)
{   my ($self, $fh) = @_;

    my $text = $self->{MMBS_scalar};
    $text    =~ s/^(?=\>*From )/>/;
    $fh->print($text);
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    delete $self->{MMBS_nrlines};

    (my $begin, my $end, $self->{MMBS_scalar}) = $parser->bodyAsString(@_);
    $self->fileLocation($begin, $end);

    $self;
}

#------------------------------------------

1;
