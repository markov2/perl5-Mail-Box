use strict;
use warnings;

package Mail::Message::Body::File;
use base 'Mail::Message::Body';

use Mail::Box::Parser;

use Carp;
use IO::File;
use POSIX 'tmpnam';
use File::Copy;

my $crlf_platform = $^O =~ m/mswin|cygwin/;

=head1 NAME

Mail::Message::Body::File - body of a message temporarily stored in a file

=head1 SYNOPSIS

 See Mail::Message::Body

=head1 DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
documentation you find the description of extra functionality you have
when a message is stored in a file.

Storing a whole message is a file is useful when the body is large.  Although
access through a file is slower, it is saving a lot of memory.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=cut

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    local $_;
    local (*IN, *OUT);

    unless(open IN, '<', $filename)
    {   $self->log(ERROR => "Unable to read file $filename: $!");
        return;
    }

    my $file   = $self->tempFilename;
    unless(open OUT, '>', $file)
    {   $self->log(ERROR => "Cannot write to $file: $!\n");
        return;
    }

    my $nrlines = 0;
    while(<IN>) { print OUT; $nrlines++ }

    close OUT;
    close IN;

    $self->{MMBF_nrlines} = $nrlines;
    $self;
}

sub _data_from_filehandle(@)
{   my ($self, $fh) = @_;
    my $file    = $self->tempFilename;
    my $nrlines = 0;

    local *OUT;

    unless(open OUT, '>', $file)
    {   $self->log(ERROR => "Cannot write to $file: $!\n");
        return;
    }

    while(my $l = $fh->getline)
    {   print OUT $l;
        $nrlines++;
    }
    close OUT;

    $self->{MMBF_nrlines} = $nrlines;
    $self;
}

sub _data_from_glob(@)
{   my ($self, $fh) = @_;
    my $file    = $self->tempFilename;
    my $nrlines = 0;

    local $_;
    local *OUT;

    unless(open OUT, '>', $file)
    {   $self->log(ERROR => "Cannot write to $file: $!\n");
        return;
    }

    while(<$fh>)
    {   print OUT;
        $nrlines++;
    }
    close OUT;

    $self->{MMBF_nrlines} = $nrlines;
    $self;
}

sub _data_from_lines(@)
{   my ($self, $lines)  = @_;
    my $file = $self->tempFilename;

    local *OUT;

    open OUT, '>', $file
        or die "Cannot write to $file: $!\n";

    print OUT @$lines;
    close OUT;

    $self->{MMBF_nrlines} = @$lines;
    $self;
}

#------------------------------------------

=head2 The Body

=cut

#------------------------------------------

sub clone()
{   my $self  = shift;
    my $clone = ref($self)->new;

    copy($self->tempFilename, $clone->tempFilename)
       or return;

    $clone->{MMBF_nrlines} = $self->{MMBF_nrlines};
    $clone->{MMBF_size}    = $self->{MMBF_size};
    $self;
}

#------------------------------------------

=head2 About the Payload

=cut

#------------------------------------------

sub nrLines()
{   my $self    = shift;
    return $self->{MMBF_nrlines} if defined $self->{MMBF_nrlines};

    my $file    = $self->tempFilename;
    my $nrlines = 0;

    local $_;
    local *IN;

    open IN, '<', $file
        or die "Cannot read from $file: $!\n";

    $nrlines++ while <IN>;
    close IN;

    $self->{MMBF_nrlines} = $nrlines;
}

#------------------------------------------

sub size()
{   my $self = shift;

    return $self->{MMBF_size} if exists $self->{MMBF_size};

    $self->{MMBF_size} = (-s $self->tempFilename)
       - ( $crlf_platform ? $self->nrLines : 0 );
}


#------------------------------------------

=head2 Access to the Payload

=cut

#------------------------------------------

sub string()
{   my $self = shift;

    my $file = $self->tempFilename;

    local *IN;

    open IN, '<', $file
        or die "Cannot read from $file: $!\n";

    my $return = join '', <IN>;
    close IN;

    $return;
}

#------------------------------------------

sub lines()
{   my $self = shift;

    my $file = $self->tempFilename;

    local *IN;
    open IN, '<', $file
        or die "Cannot read from $file: $!\n";

    my @r = <IN>;
    close IN;

    $self->{MMBF_nrlines} = @r;
    wantarray ? @r: \@r;
}

#------------------------------------------

sub file() { IO::File->new(shift->tempFilename, 'r') }

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    my $file = $self->tempFilename;

    local $_;
    local *IN;

    open IN, '<', $file
        or croak "Cannot read from $file: $!\n";

    if(ref $fh eq 'GLOB') {print $fh $_ while <IN>}
    else {$fh->print($_) while <IN>}
    close IN;

    $self;
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    my $file = $self->tempFilename;

    local *OUT;

    open OUT, '>', $file
        or die "Cannot write to $file: $!.\n";

    (my $begin, my $end, $self->{MMBF_nrlines}) = $parser->bodyAsFile(\*OUT,@_);
    close OUT;

    $self->fileLocation($begin, $end);
    $self;
}

#------------------------------------------

=method tempFilename [FILENAME]

Returns the name of the temporary file which is used to store this body.

=cut

sub tempFilename(;$)
{   my $self = shift;

      @_                     ? ($self->{MMBF_filename} = shift)
    : $self->{MMBF_filename} ? $self->{MMBF_filename}
    :                          ($self->{MMBF_filename} = tmpnam);
}

#------------------------------------------

=method DESTROY

The temporary file is automatically removed when the body is
not required anymore.

=cut

sub DESTROY { unlink shift->tempFilename }

#------------------------------------------

1;