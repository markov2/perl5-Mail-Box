use strict;
use warnings;

package Mail::Message::Head::Complete;
use base 'Mail::Message::Head';

use Mail::Box::Parser;

use Carp;
use Date::Parse;

our $VERSION = 2.016;

use overload qq("") => 'toString';

=head1 NAME

Mail::Message::Head::Complete - the header of one message

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

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Head> (MMH).

The general methods for C<Mail::Message::Head::Complete> objects:

  MMH add ...                              new OPTIONS
  MMH build FIELDS                     MMH nrLines
  MMH count NAME                       MMH print [FILEHANDLE]
  MMH delete NAME                      MMH printUndisclosed [FILEHANDLE]
   MR errors                            MR report [LEVEL]
  MMH get NAME [,INDEX]                 MR reportAll [LEVEL]
  MMH isDelayed                        MMH reset NAME, FIELDS
  MMH isMultipart                      MMH set ...
  MMH isResent                         MMH size
  MMH knownNames                       MMH timestamp
   MR log [LEVEL [,STRINGS]]           MMH toString
  MMH modified [BOOL]                   MR trace [LEVEL]
  MMH names                             MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                          MMH load
  MMH addNoRealize FIELD                MR logPriority LEVEL
  MMH clone [FIELDS]                    MR logSettings
  MMH createFromLine                   MMH message [MESSAGE]
  MMH createMessageId                  MMH moveLocation DISTANCE
  MMH fileLocation                      MR notImplemented
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH read PARSER
  MMH guessBodySize                    MMH setNoRealize FIELD
  MMH guessTimestamp                   MMH wrapLength [CHARS]

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message header object.  The object will store all the
fields of a header.

The following options can be specified:

 OPTION      DEFINED BY              DEFAULT
 field_type  Mail::Message::Head     'Mail::Message::Field::Fast'
 log         Mail::Reporter          'WARNINGS'
 message     Mail::Message::Head     undef
 modified    Mail::Message::Head     0
 trace       Mail::Reporter          'WARNINGS'
 wrap_length Mail::Message::Head     72

No options are specific to a C<Mail::Message::Head::Complete>

=cut

#------------------------------------------

sub add(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

    # Create object for this field.

    my $field;
    if(@_==1 && ref $_[0])   # A fully qualified field is added.
    {   $field = shift;
        confess "Add field to header requires $type but got ".ref($field)."\n"
            unless $field->isa($type);
    }
    else { $field = $type->new(@_) }

    $field->setWrapLength($self->{MMH_wrap_length});

    # Put it in place.

    my $known = $self->{MMH_fields};
    my $name  = $field->name;  # is already lower-cased

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    if(defined $known->{$name})
    {   if(ref $known->{$name} eq 'ARRAY') { push @{$known->{$name}}, $field }
        else { $known->{$name} = [ $known->{$name}, $field ] }
    }
    else
    {   $known->{$name} = $field;
    }

    $self->{MMH_modified}++;
    $field;
}

#------------------------------------------

my @skip_none = qw/content-transfer-encoding content-disposition/;
my %skip_none = map { ($_ => 1) } @skip_none;

sub set(@)
{   my $self = shift;
    my $type = $self->{MMH_field_type} || 'Mail::Message::Field::Fast';

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

    my $name  = $field->name;         # is already lower-cased
    my $known = $self->{MMH_fields};

    # Internally, non-existing content-info are in the body stored as 'none'
    # The header will not contain these lines.

    if($skip_none{$name} && $field->body eq 'none')
    {   delete $known->{$name};
        return $field;
    }

    # Put it in place.

    $field->setWrapLength($self->{MMH_wrap_length});

    push @{$self->{MMH_order}}, $name
        unless exists $known->{$name};

    $known->{$name} = $field;
    $self->{MMH_modified}++;

    $field;
}

#------------------------------------------

sub reset($@)
{   my ($self, $name) = (shift, lc shift);
    my $known = $self->{MMH_fields};

    if(@_==0)    { undef $known->{$name}  }
    elsif(@_==1) { $known->{$name} = shift }
    else         { $known->{$name} = [@_]  }

    $self->{MMH_modified}++;
    $self;
}
 
#------------------------------------------

sub count($)
{   my $known = shift->{MMH_fields};
    my $value = $known->{lc shift};

      ! defined $value ? 0
    : ref $value       ? @$value
    :                    1;
}

#------------------------------------------

sub names() {shift->knownNames}
 
#------------------------------------------

sub print(;$)
{   my $self  = shift;
    my $fh    = shift || select;

    my $known = $self->{MMH_fields};

    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");

    $self;
}

sub printUndisclosed($)
{   my ($self, $fh) = @_;

    my $known = $self->{MMH_fields};
    foreach my $name (@{$self->{MMH_order}})
    {   next if $name eq 'Resent-Bcc' || $name eq 'Bcc';
        my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        $_->print($fh) foreach @this;
    }

    $fh->print("\n");
    $self;
}

#------------------------------------------

sub toString()
{   my $self  = shift;
    my $known = $self->{MMH_fields};

    my @lines;
    foreach my $name (@{$self->{MMH_order}})
    {   my $this = $known->{$name} or next;
        my @this = ref $this eq 'ARRAY' ? @$this : $this;
        push @lines, $_->toString foreach @this;
    }

    push @lines, "\n";
    wantarray ? @lines : join('', @lines);
}

#------------------------------------------

sub isDelayed() {0}

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

sub clone(;@)
{   my $self   = shift;
    my $copy   = ref($self)->new($self->logSettings);

    foreach my $name ($self->grepNames(@_))
    {   $copy->add($_->clone) foreach $self->get($name);
    }

    $copy;
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
    {   foreach (reverse $self->get('received'))
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

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
