
use strict;
use warnings;

package Mail::Reporter;

our $VERSION = 2.007;

use Carp;

=head1 NAME

Mail::Reporter - manage errors and traces for various Mail::* modules

=head1 SYNOPSIS

   $folder->log(WARNING => 'go away');
   print $folder->trace;        # current level
   $folder->trace('PROGRESS');  # set level
   print $folder->errors;
   print $folder->report('PROGRESS');

=head1 DESCRIPTION

Read C<Mail::Box-Overview> first.  There are a few objects which produce
error messages, but which will not break the program.  For instance, an
erroneous message doesn't break a whole folder.

The C<Mail::Reporter> class is the base class for each object which can
produce errors, and can be configured for each mailbox, mail message,
and mail manager separately.

=head1 METHOD INDEX

The general methods for C<Mail::Reporter> objects:

      errors                               report [LEVEL]
      log [LEVEL [,STRINGS]]               reportAll [LEVEL]
      new OPTIONS                          trace [LEVEL]

The extra methods for extension writers:

      AUTOLOAD                             logPriority LEVEL
      DESTROY                              logSettings
      inGlobalDestruction                  notImplemented

=head1 METHODS

The C<Mail::Reporter> class is the base for nearly all other
objects.  It can store and report problems, and contains the general
constructor C<new()>.

=over 4

=item new OPTIONS

This error container is also the base constructor for all modules, (as long
as there is no need for an other base object)  The constructor accepts the
following arguments related to the errors:

 OPTION         DEFINED BY             DEFAULT
 log            Mail::Reporter         'WARNINGS'
 trace          Mail::Reporter         'WARNINGS'

=over 4

=item * log =E<gt> LEVEL

Log messages which have a priority higher or equal to the specified
level are stored internally and can be retrieved later. The default log
level is C<WARNINGS>,

Known levels are C<'INTERNAL'>, C<'ERRORS'>, C<'WARNINGS'>, C<'PROGRESS'>,
C<'NOTICES'> C<'DEBUG'>, and C<'NONE'>.  The C<PROGRESS> level relates to
the reading and writing of folders.  C<NONE> only will cause only C<INTERNAL>
errors to be logged.

By the way: C<ERROR> is an alias for C<ERRORS>, as C<WARNING> is an alias
for C<WARNINGS>, and C<NOTICE> for C<NOTICES>.

=item * trace =E<gt> LEVEL

Trace messages which have a level higher or equal to the specified level
are directly printed using warn.  The default trace-level is C<WARNINGS>.

=back

=cut

# synchronize this with C code in Mail::Box::Parser.
my @levelname = (undef, qw(DEBUG NOTICE PROGRESS WARNING ERROR NONE INTERNAL));

my %levelprio = (ERRORS => 5, WARNINGS => 4, NOTICES => 2);
for(my $l = 1; $l < @levelname; $l++)
{   $levelprio{$levelname[$l]} = $l;
    $levelprio{$l} = $l;
}

#sub new(@) {(bless {}, shift)->init( {@_} ) }
sub new(@) {my $class = shift; my$self =(bless {}, $class);
confess if @_ % 2;
confess unless $self->can('init'); $self->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{MR_log}   = $levelprio{$args->{log}   || 'WARNING'};
    $self->{MR_trace} = $levelprio{$args->{trace} || 'WARNING'};
    $self;
}

#------------------------------------------

=item trace [LEVEL]

Change the trace level of the object.  It returns the number which
is internally used to represent the level.

=cut

sub trace(;$)
{   my $self = shift;
    return $levelname[$self->{MR_trace}] unless @_;

    my $level = shift;
    my $prio  = $levelprio{$level}
        or croak "Unknown trace-level $level.";

    $self->{MR_trace} = $prio;
}

#------------------------------------------

=item log [LEVEL [,STRINGS]]

This method has three uses.  Without any argument, it returns the name
of the current log level.  With one argument, a new level of logging
detail is set.  With more arguments, it is a report which may need to be
logged or traced.

Each log-entry has a LEVEL (see above), and a text string which will
be constructed by joining the STRINGS.  If there is no newline, it will
be added.

Examples:

   print $message->log;      # may print   NOTICE
   $message->log('ERRORS');  # sets a new level

   $message->log(WARNING => "This message is too large.");
   $folder ->log(NOTICE  => "Cannot read from file $filename.");
   $manager->log(DEBUG   => "Hi there!", reverse sort @l);

=cut

# Implementation detail: the C code avoids calls back to Perl by
# checking the trace-level itself.  In the perl code of this module
# however, just always call the log() method, and let it check
# whether or not to display it.

sub log(;$@)
{   my $self = shift;
    return $levelname[$self->{MR_log}] unless @_;

    my $level = shift;
    my $prio  = $levelprio{$level}
        or croak "Unknown log-level $level.";

    return $self->{MR_log} = $prio unless @_;

    my $text    = join '', @_;
    $text      .= "\n" unless (substr $text, -1) eq "\n";

    warn "$level: $text"
        if $prio >= $self->{MR_trace};

    push @{$self->{MR_report}[$prio]}, $text
        if $prio >= $self->{MR_log};

    $self;
}


#------------------------------------------

=item report [LEVEL]

Get logged reports, as list of strings.  If a LEVEL is specified, the log
for that level is returned.

In case no LEVEL is specified, you get all messages each as reference
to a tuple with level and message.

Examples:

   my @warns = $message->report('WARNINGS');
      # previous indirectly callable with
      my @warns = $msg->warnings;

   print $folder->report('ERRORS');

   if($folder->report('DEBUG')) {...}

   my @reports = $folder->report;
   foreach (@reports) {
       my ($level, $text) = @$_;
       print "$level report: $text";
   }

=cut

sub report(;$)
{   my $self    = shift;
    my $reports = $self->{MR_report} || return ();

    if(@_)
    {   my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown report level $level.";

        return $reports->[$prio] ? @{$reports->[$prio]} : ();
    }

    my @reports;
    for(my $prio = 1; $prio < @$reports; $prio++)
    {   next unless $reports->[$prio];
        my $level = $levelname[$prio];
        push @reports, map { [ $level, $_ ] } @{$reports->[$prio]};
    }

    @reports;
}

#-------------------------------------------

=item reportAll [LEVEL]

Report all messages which were produced by this object and all the objects
which are maintained by this object.  This will return a list of triplets,
each containing a reference to the object which caught the report, the
level of the report, and the message.

Example:

    my $folder = Mail::Box::Manager->new->open(folder => 'inbox');
    my @reports = $folder->reportAll;
    foreach (@reports) {
        my ($object, $level, $text) = @$_;

        if($object->isa('Mail::Box')) {
            print "Folder $object: $level: $message";
        } elsif($object->isa('Mail::Message') {
            print "Message ".$object->seqnr.": $level: $message";
        }
    }

=cut

sub reportAll(;$)
{   my $self = shift;
    map { [ $self, @$_ ] } $self->report(@_);
}

#-------------------------------------------

=item errors

=item warnings

Equivalent to

   $folder->report('ERRORS');     # and
   $folder->report('WARNINGS');

=cut

sub errors(@)   {shift->report('ERRORS')}
sub warnings(@) {shift->report('WARNINGS')}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item notImplemented

A special case of the above C<log()>, which logs a C<INTERNAL>-error
and then croaks.  This is used by extension writers.

=cut

sub notImplemented(@)
{   my $self = shift;
    my ($package, $sub) = (caller 1)[0,3];

confess;
    $self->log(INTERNAL => "$package does not implement $sub.");
    croak "Please warn the author, this shouldn't happen.";
}

#------------------------------------------

=item logPriority LEVEL

(Class and instance method)   Returns the priority of the named level as
numeric value.  The higher the number, the more important the message.
Only messages about C<INTERNAL> problems are more important than C<NONE>.

=cut

sub logPriority($) { $levelprio{$_[1]} }

#-------------------------------------------

=item logSettings

Returns a list of (key => value) pairs which can be used to initiate
a new object with the same log-settings as this one.

Example:

   $head->new($folder->logSettings);

=cut

sub logSettings()
{  my $self = shift;
   (log => $self->{MR_log}, trace => $self->{MR_trace});
}

#-------------------------------------------

=item inGlobalDestruction

Returns whether the program is breaking down.  This is used in DESTROY,
where during global destructions references cannot be used.

=cut

my $global_destruction;
END {$global_destruction++}
sub inGlobalDestruction() {$global_destruction}

#-------------------------------------------

=item DESTROY

Cleanup.

=cut

sub DESTROY {shift}

#-------------------------------------------

=item AUTOLOAD

produce a nice warning if the sub-classes cannot resolve a method.

=cut

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    confess "Failed calling $AUTOLOAD, arguments: \n@_\n";
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.007.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
