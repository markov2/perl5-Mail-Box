use strict;

package Mail::Box::IMAP4::Head;
use base 'Mail::Message::Head';

use Date::Parse;

=chapter NAME

Mail::Box::IMAP4::Head - header fields related IMAP interface

=chapter SYNOPSIS

=chapter DESCRIPTION

This class implements a pure IMAP4 protocol interface, where as little
data is retrieved from the header as possible.  This may look nice
to you, but is not sufficient for many tasks.  For instance, you cannot
removed or modify fields this way.

Change M<Mail::Box::IMAP4::new(cache_head)> to C<YES> or C<DELAY>, to
get a message header which is capable of performing all possible
games with headers.  On the other hand: the other settings are not
100% safe...

=chapter METHODS

=c_method new %options

=option  cache_fields BOOLEAN
=default cache_fields C<false>
This is only a read-cache on fields, because this kind of header does
not allow writing of fields.  See M<Mail::Box::IMAP4::new(cache_head)>,
this value is set to C<false> for C<NO> and C<true> for C<PARTIAL>..

=cut

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBIH_c_fields} = $args->{cache_fields};
    $self;
}

=method get $name, [$index]
Get the information about the header line $name.  Realization will
take place.
=cut

sub get($;$)
{   my ($self, $name, $index) = @_;

       if(not $self->{MBIH_c_fields}) { ; }
    elsif(wantarray)
    {   my @values = $self->SUPER::get(@_);
        return @values if @values;
    }
    else
    {   my $value  = $self->SUPER::get(@_);
        return $value  if defined $value;
    }

    # Something here, playing with ENVELOPE, may improve the performance
    # as well.
    my $imap   = $self->message->folder->transporter;
    my $uidl   = $self->message->unique;
    my @fields = $imap->getFields($uidl, $name);

    if(@fields && $self->{MBIH_c_fields})
    {   $self->addNoRealize($_) for @fields
    }

      defined $index ? $fields[$index]
    : wantarray      ? @fields
    :                  $fields[0];
}

sub guessBodySize() {undef}

sub guessTimestamp() {undef}

#------------------------------------------

=section Internals

=cut

1;
