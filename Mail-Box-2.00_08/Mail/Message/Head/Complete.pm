use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Date::Parse;

our $VERSION = '2.00_08';

#use overload qq("") => 'toString';

=head1 NAME

 Mail::Message::Head::Complete - the header of one Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Head::Complete
 is a Mail::Message::Head
 is a Mail::Reporter

=head1 SYNOPSIS

 my $head = Mail::Message::Head::Complete->new;
 See Mail::Message::Head

=head1 DESCRIPTION

A mail's message can be in various states: unread, partially read, and
fully read.  The class stores a message of which all header lines are
known for sure.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head::Complete> objects:

  MMH add ...                          MMH nrLines
  MMH clone [FIELDS]                   MMH print FILE [,LINE-LENGTH]
      count NAME                        MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MMH get NAME [,INDEX]                MMH reset NAME, FIELDS
  MMH isDelayed                        MMH set ...
  MMH isMultipart                      MMH size
   MR log [LEVEL [,STRINGS]]           MMH timestamp
  MMH names                             MR trace [LEVEL]
      new OPTIONS                       MR warnings

The extra methods for extension writers:

  MMH createFromLine                    MR logPriority LEVEL
  MMH createMessageId                   MR logSettings
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH message [MESSAGE]
  MMH guessBodySize                     MR notImplemented
  MMH guessTimestamp                   MMH read PARSER
  MMH load                             MMH wrapLength [CHARS]

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMH = L<Mail::Message::Head>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message header object.  The object will store all the
fields of a header.

The following options can be specified:

 OPTION      DEFINED BY              DEFAULT
 field_type  Mail::Message::Head     'Mail::Message::Field'
 log         Mail::Reporter          'WARNINGS'
 message     Mail::Message::Head     undef
 trace       Mail::Reporter          'WARNINGS'
 wrap_length Mail::Message::Head     72

No options are specific to a C<Mail::Message::Head::Complete>

=cut

#------------------------------------------

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new($self->logSettings);

    foreach my $name ($self->grepNames(@_))
    {   $copy->add($_->clone) foreach $self->get($name);
    }

    $copy;
}

#------------------------------------------

sub isDelayed() {0}

#------------------------------------------

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else
    {   $field = $type->new(@_);
    }

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $field;
}

#------------------------------------------

=item count NAME

Count the number of fields for this NAME.

=cut

sub count($)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};

      ! defined $value ? 0
    : ref $value       ? @$value
    :                    1;
}

#------------------------------------------

sub reset($@)
{   my ($self, $name) = (shift, lc shift);
    my $known = $self->{MMH_fields};

    if(@_==0)    { undef $known->{$name}  }
    elsif(@_==1) { $known->{$name} = shift }
    else         { $known->{$name} = [@_]  }

    $self;
}
 
#------------------------------------------

sub print($)
{   my ($self, $fh) = @_;
    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");

    $self;
}

#------------------------------------------

sub nrLines()
{   my $self = shift;
    my $nr   = 1;  # trailing

    foreach my $name ($self->names)
    {   $nr += $_->nrLines foreach $self->get($name);
    }
    $nr;
}

#------------------------------------------

sub size()
{   my $self  = shift;
    my $bytes = 1;  # trailing blank
    foreach my $name ($self->names)
    {   $bytes += $_->size foreach $self->get($name);
    }
    $bytes;
}

#------------------------------------------

sub timestamp() {shift->guessTimestamp || time}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub guessTimestamp()
{   my $self = shift;
    return $self->{MMH_timestamp} if $self->{MMH_timestamp};

    my $stamp;
    if(my $date = $self->get('date'))
    {   $stamp = str2time($date, 'GMT');
    }

    unless($stamp)
    {   foreach ($self->get('received'))
        {   $stamp = str2time($_, 'GMT');
            last if $stamp;
        }
    }

    $self->{MBM_timestamp} = $stamp;
}

#------------------------------------------

sub guessBodySize()
{   my $self = shift;

    my $cl = $self->get('Content-Length');
    return $1 if defined $cl && $cl =~ m/(\d+)/;

    my $lines = $self->get('Lines');   # 40 chars per lines
    return $1*40 if defined $lines && $lines =~ m/(\d+)/;

    undef;
}

#------------------------------------------

sub createFromLine()
{   my $self   = shift;

    my $from   = $self->get('from') || '';
    my $stamp  = $self->timestamp;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
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

This code is beta, version 2.00_08.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
