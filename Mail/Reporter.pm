
use strict;
use warnings;

package Mail::Reporter;

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

=head1 METHODS

The C<Mail::Reporter> class is the base for nearly all other
objects.  It can store and report problems, and contains the general
constructor new().

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

This error container is also the base constructor for all modules, (as long
as there is no need for an other base object)  The constructor always accepts
the following OPTIONS related to error reports.

=option  log LEVEL
=default log 'WARNINGS'

Log messages which have a priority higher or equal to the specified
level are stored internally and can be retrieved later.  The global
default for this option can be changed with defaultTrace().

Known levels are C<'INTERNAL'>, C<'ERRORS'>, C<'WARNINGS'>, C<'PROGRESS'>,
C<'NOTICES'> C<'DEBUG'>, and C<'NONE'>.  The C<PROGRESS> level relates to
the reading and writing of folders.  C<NONE> will cause only C<INTERNAL>
errors to be logged.
By the way: C<ERROR> is an alias for C<ERRORS>, as C<WARNING> is an alias
for C<WARNINGS>, and C<NOTICE> for C<NOTICES>.

=option  trace LEVEL
=default trace 'WARNINGS'

Trace messages which have a level higher or equal to the specified level
are directly printed using warn.  The global default for this option can
be changed with defaultTrace().

=cut

# synchronize this with C code in Mail::Box::Parser.
my @levelname = (undef, qw(DEBUG NOTICE PROGRESS WARNING ERROR NONE INTERNAL));

my %levelprio = (ERRORS => 5, WARNINGS => 4, NOTICES => 2);
for(my $l = 1; $l < @levelname; $l++)
{   $levelprio{$levelname[$l]} = $l;
    $levelprio{$l} = $l;
}

sub new(@) {my $class = shift; (bless {}, $class)->init({@_}) }

my $default_log   = $levelprio{WARNINGS};
my $default_trace = $levelprio{WARNINGS};

sub init($)
{   my ($self, $args) = @_;
    $self->{MR_log}   = $levelprio{$args->{log}   || $default_log};
    $self->{MR_trace} = $levelprio{$args->{trace} || $default_trace};
    $self;
}

#------------------------------------------

=head2 Logging and Tracing

=cut

#------------------------------------------

=method defaultTrace [LEVEL, [LEVEL]

(Class method)
Reports the default trace and log level which is used for object as list
of two elements.  When not explicitly set, both are set to C<WARNINGS>.

You may specify one or two arguments.  In case of one argument, the
default log and trace levels will both be set to that value.  When two
levels are specified, the first represent the default log-level and
the second the default trace level.

=examples

 my ($loglevel, $tracelevel) = Mail::Reporter->defaultTrace;
 Mail::Reporter->defaultTrace('NOTICES');
 Mail::Reporter->defaultTrace('WARNINGS', 'INFO');

=cut

sub defaultTrace(;$$)
{   my $self = shift;
    return ($default_log, $default_trace) unless @_;

    ($default_log, $default_trace) = @_==1 ? ($_[0], $_[0]) : @_;
}

#------------------------------------------

=method trace [LEVEL]

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

=method log [LEVEL [,STRINGS]]

(Class or Instance method)
As instance method this function has three different purposes.  Without
any argument, it returns the name of the current log level.  With one
argument, a new level of logging detail is set.  With more arguments, it
is a report which may need to be logged or traced.

As class method, only a message can be passed.  The global configuration
value set with defaultTrace() is used to decide whether the message is
shown or ignored.

Each log-entry has a LEVEL and a text string which will
be constructed by joining the STRINGS.  If there is no newline, it will
be added.

=examples

 print $message->log;      # may print   NOTICE
 $message->log('ERRORS');  # sets a new level

 $message->log(WARNING => "This message is too large.");
 $folder ->log(NOTICE  => "Cannot read from file $filename.");
 $manager->log(DEBUG   => "Hi there!", reverse sort @l);

 Mail::Message->log(ERROR => 'Unknown');

=cut

# Implementation detail: the C code avoids calls back to Perl by
# checking the trace-level itself.  In the perl code of this module
# however, just always call the log() method, and let it check
# whether or not to display it.

sub log(;$@)
{   my $thing = shift;

    if(ref $thing)   # instance call
    {   return $levelname[$thing->{MR_log}] unless @_;

        my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level.";

        return $thing->{MR_log} = $prio unless @_;

        my $text    = join '', @_;
        $text      .= "\n" unless (substr $text, -1) eq "\n";

        warn "$level: $text"
            if $prio >= $thing->{MR_trace};

        push @{$thing->{MR_report}[$prio]}, $text
            if $prio >= $thing->{MR_log};
    }
    else             # class method
    {   my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level.";

        return $thing unless $prio >= $default_trace;

        my $text    = join '', @_;
        $text      .= "\n" unless (substr $text, -1) eq "\n";

        warn "$level: $text";
    }

    $thing;
}


#------------------------------------------

=method report [LEVEL]

Get logged reports, as list of strings.  If a LEVEL is specified, the log
for that level is returned.

In case no LEVEL is specified, you get all messages each as reference
to a tuple with level and message.

=examples

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

=method reportAll [LEVEL]

Report all messages which were produced by this object and all the objects
which are maintained by this object.  This will return a list of triplets,
each containing a reference to the object which caught the report, the
level of the report, and the message.

=examples

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

=method errors

Equivalent to C<< $folder->report('ERRORS') >>

=cut

sub errors(@)   {shift->report('ERRORS')}

#-------------------------------------------

=method warnings

Equivalent to C<< $folder->report('WARNINGS') >>

=cut

sub warnings(@) {shift->report('WARNINGS')}

#-------------------------------------------

=head2 Other Methods

=cut

#------------------------------------------

=method notImplemented

A special case of the above log(), which logs a C<INTERNAL>-error
and then croaks.  This is used by extension writers.

=cut

sub notImplemented(@)
{   my $self    = shift;
    my $package = ref $self || $self;
    my $sub     = (caller 1)[3];

    $self->log(INTERNAL => "$package does not implement $sub.");
    confess "Please warn the author, this shouldn't happen.";
}

#------------------------------------------

=method logPriority LEVEL

(Class and instance method)   Returns the priority of the named level as
numeric value.  The higher the number, the more important the message.
Only messages about C<INTERNAL> problems are more important than C<NONE>.

=cut

sub logPriority($) { $levelprio{$_[1]} }

#-------------------------------------------

=method logSettings

Returns a list of (key => value) pairs which can be used to initiate
a new object with the same log-settings as this one.

=examples

 $head->new($folder->logSettings);

=cut

sub logSettings()
{  my $self = shift;
   (log => $self->{MR_log}, trace => $self->{MR_trace});
}

#-------------------------------------------

=method inGlobalDestruction

Returns whether the program is breaking down.  This is used in DESTROY,
where during global destructions references cannot be used.

=cut

my $global_destruction;
END {$global_destruction++}
sub inGlobalDestruction() {$global_destruction}

#-------------------------------------------

=method DESTROY

Cleanup.

=cut

sub DESTROY {shift}

#-------------------------------------------

=method AUTOLOAD

produce a nice warning if the sub-classes cannot resolve a method.

=cut

sub AUTOLOAD(@)
{   my $self  = shift;
    our $AUTOLOAD;
    my $class = ref $self;
    (my $method = $AUTOLOAD) =~ s/^$class\:\://;

    $Carp::MaxArgLen=20;
    confess "Method $method() is not defined for a $class.\n";
}

#-------------------------------------------

1;
