use strict;
use warnings;

package Mail::Message::Field::Address;
use base 'Mail::Reporter';

use Mail::Message::Field::Full;
my $format = 'Mail::Message::Field::Full';

=chapter NAME

Mail::Message::Field::Address - One e-mail address

=chapter SYNOPSIS

 !! UNDER CONSTRUCTION !!

=chapter DESCRIPTION

=chapter METHODS

=c_method new DATA

=option  name STRING
=default name C<''>

=option  local STRING
=default local undef

=option  domain STRING
=default domain undef

=option  address STRING
=default address undef

=option  comment STRING
=default comment undef

=option  loccomment STRING
=default loccomment  undef

=option  domcomment STRING
=default domcomment undef

=examples

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return;

    $self->{MMFA_name} = $args->{name};

    @$self{ qw/MMFA_local MMFA_domain/ }
     = defined $args->{address} ? (split /\@/, $args->{address}, 2)
     : (@$args{ qw/local domain/ });

    $self;
}

#------------------------------------------

=section Access to the content

=method name

=cut

sub name() { shift->{MMFA_name} }

#------------------------------------------

=method address

=cut

sub address()
{   my $self  = shift;
    my @parts = $self->{MMFA_local};

    push @parts, $format->createComment($self->{MMFA_loccomment})
       if exists $self->{MMFA_loccomment};

    push @parts, '@', $self->{MMFA_domain};

    push @parts, $format->createComment($self->{MMFA_domcomment})
       if exists $self->{MMFA_domcomment};
    
    join '', @parts;
}

#------------------------------------------

=method string

=cut

sub string()
{   my $self    = shift;
    my @parts;

    my $name    = $self->name;
    push @parts, $format->createPhrase($name) if defined $name;

    my $address = $self->address;
    push @parts, defined $name ? '<'.$address.'>' : $address;

    push @parts, $format->createComment($self->{MMFA_comment})
       if exists $self->{MMFA_comment};

    join ' ', @parts;
}

#------------------------------------------

=section Error handling

=cut


1;
