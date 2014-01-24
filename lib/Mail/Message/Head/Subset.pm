
use strict;

package Mail::Message::Head::Subset;
use base 'Mail::Message::Head';

use Object::Realize::Later
    becomes        => 'Mail::Message::Head::Complete',
    realize        => 'load',
    believe_caller => 1;

use Date::Parse;

=chapter NAME

Mail::Message::Head::Subset - subset of header information of a message

=chapter SYNOPSIS

 my $subset = Mail::Message::Head::Subset->new(...)
 $subset->isa('M<Mail::Message::Head>')  # true
 $subset->guessBodySize               # integer or undef
 $subset->isDelayed                   # true

=chapter DESCRIPTION

Some types of folders contain an index file which lists a few lines of
information per messages.  Especially when it is costly to read header lines,
the index speeds-up access considerably.  For instance, the subjects of
all messages are often wanted, but waiting for a thousand messages of the
folder to be read may imply a thousand network reads (IMAP) or file
openings (MH)

When you access header fields which are not in the header subset, the whole
header has to be parsed (which may consume considerable time, depending on
the type of folder).

=chapter METHODS

=section Access to the header

=method count $name
Count the number of fields with this $name.  If the $name cannot be found,
the full header get loaded.  In case we find any $name field, it is
decided we know all of them, and loading is not needed.
=cut

sub count($)
{   my ($self, $name) = @_;
    my @values = $self->get($name)
        or return $self->load->count($name);
    scalar @values;
}

=method get $name, [$index]
Get the data which is related to the field with the $name.  The case of the
characters in $name does not matter.  When a $name is used which is not known
yet, realization will take place.
=cut

sub get($;$)
{   my $self = shift;
 
    if(wantarray)
    {   my @values = $self->SUPER::get(@_);
        return @values if @values;
    }
    else
    {   my $value  = $self->SUPER::get(@_);
        return $value  if defined $value;
    }

    $self->load->get(@_);
}


#-------------------------------------------
=section About the body

=method guessBodySize
The body size is defined in the C<Content-Length> field.  However, this
field may not be known.  In that case, a guess is made based on the known
C<Lines> field.  When also that field is not known yet, C<undef> is returned.
=cut

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->SUPER::get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->SUPER::get('Lines');   # 40 chars per lines
    return $1*40 if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#-------------------------------------------
# Be careful not to trigger loading: this is not the thoroughness
# we want from this method.

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMHS_timestamp} if $self->{MMHS_timestamp};

    my $stamp;
    if(my $date = $self->SUPER::get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach ($self->SUPER::get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MMHS_timestamp} = $stamp;
}

#-------------------------------------------
=section Internals
=cut

sub load() { $_[0] = $_[0]->message->loadHead }

1;
