use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Date::Parse;

our $VERSION = '2.00_06';

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

  MMH add ...                           MR log [LEVEL [,STRINGS]]
  MMH clone [FIELDS]                   MMH message [MESSAGE]
  MMH count NAME                       MMH names
  MMH createFromLine                       new OPTIONS
  MMH createMessageId                  MMH print FILE [,LINE-LENGTH]
   MR errors                            MR report [LEVEL]
  MMH get NAME [,INDEX]                 MR reportAll [LEVEL]
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH reset NAME, FIELDS
  MMH guessBodySize                    MMH set ...
  MMH guessTimestamp                   MMH timestamp
  MMH isDelayed                         MR trace [LEVEL]
  MMH isMultipart                       MR warnings

The extra methods for extension writers:

  MMH load                              MR notImplemented
   MR logPriority LEVEL                MMH read PARSER

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

 OPTION         DEFINED BY              DEFAULT
 complete_type  Mail::Message::Head     <not used>
 field_type     Mail::Message::Head     'Mail::Message::Field'
 log            Mail::Reporter          'WARNINGS'
 message        Mail::Message::Head     undef
 trace          Mail::Reporter          'WARNINGS'

No options are specific to a C<Mail::Message::Head::Complete>

=back

=cut

#------------------------------------------

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new(log => $self->log, trace => $self->trace);

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

sub print($;$)
{   my ($self, $fh, @options) = @_;
    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh, @options) foreach @this;
    }

    $fh->print("\n");

    $self;
}

#------------------------------------------

sub read($)
{   my ($self, $parser) = @_;

    my $pairs = [ $parser->readHeader ];    # avoid copying elements
    $self->{MMH_start} = shift @$pairs;

    while(@$pairs)
    {   my $name = lc (shift @$pairs);
        $self->add($name, shift @$pairs);
    }

    $self;
}

sub start {shift->{MMH_start}}

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

sub timestamp() {shift->guessTimestamp || time}

#------------------------------------------

sub createFromLine()
{   my $self   = shift;

    my $from   = $self->get('from') || '';
    my $stamp  = $self->timestamp;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    "From $sender ".(gmtime $stamp)."\n";
}

#------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_06.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
