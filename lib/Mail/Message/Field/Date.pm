use warnings;
use strict;

package Mail::Message::Field::Date;
use base 'Mail::Message::Field::Structured';

use POSIX qw/mktime tzset/;

=chapter NAME

Mail::Message::Field::Date - message header field with uris

=chapter SYNOPSIS

 my $f = Mail::Message::Field->new(Date => time);

=chapter DESCRIPTION
Dates are a little more tricky than it should be: the formatting permits
a few constructs more than other RFCs use for timestamps.  For instance,
a small subset of timezone abbreviations are permitted.

The studied date field will reformat the content into a standard
form.

=chapter METHODS

=section Constructors

=c_method new $data
=default attributes <ignored>

=examples
 my $mmfd = 'Mail::Message::Field::Date';
 my $f = $mmfd->new(Date => time);
=cut

my $dayname = qr/Mon|Tue|Wed|Thu|Fri|Sat|Sun/;
my @months  = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
my %monthnr; { my $i; $monthnr{$_} = ++$i for @months }
my %tz      = qw/EDT -0400  EST -0500  CDT -0500  CST -0600
                 MDT -0600  MST -0700  PDT -0700  PST -0800
                 UT  +0000  GMT +0000/;

sub parse($)
{   my ($self, $string) = @_;

    my ($dn, $d, $mon, $y, $h, $min, $s, $z) = $string =~
      m/ ^ \s*
           (?: ($dayname) \s* \, \s* )?
           ( 0?[1-9] | [12][0-9] | 3[01] ) \s* # day
           \s+ ( [A-Z][a-z][a-z] ) \s+         # month
           ( 19[0-9][0-9] | 2[0-9]{3} ) \s+    # year
                  ( [0-1]?[0-9] | 2[0-3] ) \s* # hour
               [:.] ( [0-5][0-9] ) \s*         # minute
           (?: [:.] ( [0-5][0-9] ) )? \s+      # second
           ( [+-][0-9]{4} | [A-Z]+ )?          # zone
           \s* /x
       or return undef;

    defined $dn or $dn = '';
    $dn  =~ s/\s+//g;

    $y  += 2000 if $y < 50;
    $y  += 1900 if $y < 100;

    $z ||= '-0000';
    $z   =  $tz{$z} || '-0000'
        if $z =~ m/[A-Z]/;

    $self->{MMFD_date} = sprintf "%s%s%02d %s %04d %02d:%02d:%02d %s"
      , $dn, (length $dn ? ', ' : ''), $d, $mon, $y, $h, $min, $s, $z;

    $self;
}

sub produceBody() { shift->{MMFD_date} }
sub date() { shift->{MMFD_date} }

#------------------------------------------

=section Access to the content

=method addAttribute ...
Attributes are not supported for date fields.

=error No attributes for date fields.
Is is not possible to add attributes to date fields: it is not permitted
by the RFCs.

=cut

sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for date fields.');
    $self;
}

=method time
Convert date into a timestamp, as produced with POSIX::time().
=cut

sub time()
{   my $date = shift->{MMFD_date};
    my ($d, $mon, $y, $h, $min, $s, $z)
      = $date =~ m/^ (?:\w\w\w\,\s+)? (\d\d)\s+(\w+)\s+(\d\d\d\d)
                     \s+ (\d\d)\:(\d\d)\:(\d\d) \s+ ([+-]\d\d\d\d)? \s*$ /x;

    my $oldtz = $ENV{TZ};
    $ENV{TZ}  = 'UTC';
    tzset;
    my $timestamp = mktime $s, $min, $h, $d, $monthnr{$mon}-1, $y-1900;
    $ENV{TZ}  = $oldtz;
    tzset;

    $timestamp += ($1 eq '-' ? 1 : -1) * ($2*3600 + $3*60)
        if $z =~ m/^([+-])(\d\d)(\d\d)$/;
    $timestamp;
}

#------------------------------------------

=section Error handling
=cut

1;
