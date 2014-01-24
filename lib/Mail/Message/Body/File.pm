use strict;
use warnings;

package Mail::Message::Body::File;
use base 'Mail::Message::Body';

use Mail::Box::Parser;
use Mail::Message;

use Carp;
use File::Temp qw/tempfile/;
use File::Copy qw/copy/;

=chapter NAME

Mail::Message::Body::File - body of a message temporarily stored in a file

=chapter SYNOPSIS

 See M<Mail::Message::Body>

=chapter DESCRIPTION

The body (content) of a message can be stored in various ways.  In this
documentation you find the description of extra functionality you have
when a message is stored in a file.

Storing a whole message is a file is useful when the body is large.  Although
access through a file is slower, it is saving a lot of memory.

=chapter METHODS

=c_method new %options

=error Unable to read file $filename for message body file: $!
A M<Mail::Message::Body::File> object is to be created from a named file, but
it is impossible to read that file to retrieve the lines within.  Therefore,
no copy to a temporary file can be made.

=error Cannot write to temporary body file $filename: $!
The message body is to be stored in a temporary file (probably because it is a
large body), but for the indicated reason, this file cannot be created.

=cut

sub _data_from_filename(@)
{   my ($self, $filename) = @_;

    local $_;
    local (*IN, *OUT);

    unless(open IN, '<:raw', $filename)
    {   $self->log(ERROR =>
            "Unable to read file $filename for message body file: $!");
        return;
    }

    my $file   = $self->tempFilename;
    unless(open OUT, '>:raw', $file)
    {   $self->log(ERROR => "Cannot write to temporary body file $file: $!");
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

    unless(open OUT, '>:raw', $file)
    {   $self->log(ERROR => "Cannot write to temporary body file $file: $!");
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

    unless(open OUT, '>:raw', $file)
    {   $self->log(ERROR => "Cannot write to temporary body file $file: $!");
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

    unless(open OUT, '>:raw', $file)
    {   $self->log(ERROR => "Cannot write to $file: $!");
        return;
    }

    print OUT @$lines;
    close OUT;

    $self->{MMBF_nrlines} = @$lines;
    $self;
}

sub clone()
{   my $self  = shift;
    my $clone = ref($self)->new(based_on => $self);

    copy($self->tempFilename, $clone->tempFilename)
       or return;

    $clone->{MMBF_nrlines} = $self->{MMBF_nrlines};
    $clone->{MMBF_size}    = $self->{MMBF_size};
    $self;
}

sub nrLines()
{   my $self    = shift;

    return $self->{MMBF_nrlines}
        if defined $self->{MMBF_nrlines};

    my $file    = $self->tempFilename;
    my $nrlines = 0;

    local $_;
    local *IN;

    open IN, '<:raw', $file
        or die "Cannot read from $file: $!\n";

    $nrlines++ while <IN>;
    close IN;

    $self->{MMBF_nrlines} = $nrlines;
}

#------------------------------------------

sub size()
{   my $self = shift;

    return $self->{MMBF_size}
       if exists $self->{MMBF_size};

    my $size = eval { -s $self->tempFilename };

    $size   -= $self->nrLines
        if $Mail::Message::crlf_platform;   # remove count for extra CR's

    $self->{MMBF_size} = $size;
}

sub string()
{   my $self = shift;

    my $file = $self->tempFilename;

    local *IN;

    open IN, '<:raw', $file
        or die "Cannot read from $file: $!\n";

    my $return = join '', <IN>;
    close IN;

    $return;
}

sub lines()
{   my $self = shift;

    my $file = $self->tempFilename;

    local *IN;
    open IN, '<:raw', $file
        or die "Cannot read from $file: $!\n";

    my @r = <IN>;
    close IN;

    $self->{MMBF_nrlines} = @r;
    wantarray ? @r: \@r;
}

sub file()
{   open my $tmp, '<:raw', shift->tempFilename;
    $tmp;
}

sub print(;$)
{   my $self = shift;
    my $fh   = shift || select;
    my $file = $self->tempFilename;

    local $_;
    local *IN;

    open IN, '<:raw', $file
        or croak "Cannot read from $file: $!\n";

    if(ref $fh eq 'GLOB') {print $fh $_ while <IN>}
    else                  {$fh->print($_) while <IN>}
    close IN;

    $self;
}

sub read($$;$@)
{   my ($self, $parser, $head, $bodytype) = splice @_, 0, 4;
    my $file = $self->tempFilename;

    local *OUT;

    open OUT, '>:raw', $file
        or die "Cannot write to $file: $!.\n";

    (my $begin, my $end, $self->{MMBF_nrlines}) = $parser->bodyAsFile(\*OUT,@_);
    close OUT;

    $self->fileLocation($begin, $end);
    $self;
}

# on UNIX always true.  Expensive to calculate on Windows: message size
# may be off-by-one in rare cases.
sub endsOnNewline() { shift->size==0 }

#------------------------------------------

=section Internals

=method tempFilename [$filename]
Returns the name of the temporary file which is used to store this body.
=cut

sub tempFilename(;$)
{   my $self = shift;

      @_                     ? ($self->{MMBF_filename} = shift)
    : $self->{MMBF_filename} ? $self->{MMBF_filename}
    :                          ($self->{MMBF_filename} = (tempfile)[1]);
}

#------------------------------------------

=section Error handling

=section Cleanup

=method DESTROY
The temporary file is automatically removed when the body is
not required anymore.
=cut

sub DESTROY { unlink shift->tempFilename }

#------------------------------------------

1;
