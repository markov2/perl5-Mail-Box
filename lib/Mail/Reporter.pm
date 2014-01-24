use strict;
use warnings;

package Mail::Reporter;

use Carp;
use Scalar::Util 'dualvar';

=chapter NAME

Mail::Reporter - base-class and error reporter for Mail::Box

=chapter SYNOPSIS

 $folder->log(WARNING => 'go away');
 print $folder->trace;        # current level
 $folder->trace('PROGRESS');  # set level
 print $folder->errors;
 print $folder->report('PROGRESS');

=chapter DESCRIPTION

The C<Mail::Reporter> class is the base class for all classes, except
M<Mail::Message::Field::Fast> because it would become slow...  This
base class is used during initiation of the objects, and for configuring
and logging error messages.

=chapter METHODS

The C<Mail::Reporter> class is the base for nearly all other
objects.  It can store and report problems, and contains the general
constructor M<new()>.

=section Constructors

=c_method new %options

This error container is also the base constructor for all modules, (as long
as there is no need for another base object)  The constructor always accepts
the following %options related to error reports.

=option  log LEVEL
=default log C<'WARNINGS'>

Log messages which have a priority higher or equal to the specified
level are stored internally and can be retrieved later.  The global
default for this option can be changed with M<defaultTrace()>.

Known levels are C<INTERNAL>, C<ERRORS>, C<WARNINGS>, C<PROGRESS>,
C<NOTICES> C<DEBUG>, and C<NONE>.  The C<PROGRESS> level relates to
the reading and writing of folders.  C<NONE> will cause only C<INTERNAL>
errors to be logged.
By the way: C<ERROR> is an alias for C<ERRORS>, as C<WARNING> is an alias
for C<WARNINGS>, and C<NOTICE> for C<NOTICES>.

=option  trace LEVEL
=default trace C<'WARNINGS'>

Trace messages which have a level higher or equal to the specified level
are directly printed using warn.  The global default for this option can
be changed with M<defaultTrace()>.

=cut

my @levelname = (undef, qw(DEBUG NOTICE PROGRESS WARNING ERROR NONE INTERNAL));

my %levelprio = (ERRORS => 5, WARNINGS => 4, NOTICES => 2);
for(my $l = 1; $l < @levelname; $l++)
{   $levelprio{$levelname[$l]} = $l;
    $levelprio{$l} = $l;
}

sub new(@)
{   my $class = shift;
#confess "Parameter list has odd length: @_" if @_ % 2;
    (bless {}, $class)->init({@_});
}

my($default_log, $default_trace, $trace_callback);
sub init($)
{   my ($self, $args) = @_;
    $self->{MR_log}   = $levelprio{$args->{log}   || $default_log};
    $self->{MR_trace} = $levelprio{$args->{trace} || $default_trace};
    $self;
}

#------------------------------------------

=section Error handling

=ci_method defaultTrace [$level]|[$loglevel, $tracelevel]|[$level, $callback]

Reports the default log and trace level which is used for object as list
of two elements.  When not explicitly set, both are set to C<WARNINGS>.

This method has three different uses. When one argument is specified, that
$level is set for both loglevel as tracelevel.

With two arguments, the second determines which configuration you like.  If
the second argument is a CODE reference, you install a $callback.  The loglevel
will be set to NONE, and all warnings produced in your program will get
passed to the $callback function.  That function will get the problem level,
the object or class which reports the problem, and the problem text passed
as arguments.

In any case two values are returned: the first is the log level, the
second represents the trace level.  Both are special variables: in numeric
context they deliver a value (the internally used value), and in string
context the string name.  Be warned that the string is always in singular
form!

=examples setting loglevels
 my ($loglevel, $tracelevel) = Mail::Reporter->defaultTrace;
 Mail::Reporter->defaultTrace('NOTICES');

 my ($l, $t) = Mail::Reporter->defaultTrace('WARNINGS', 'DEBUG');
 print $l;     # prints "WARNING"  (no S!)
 print $l+0;   # prints "4"
 print "Auch" if $l >= $self->logPriority('ERROR');

 Mail::Reporter->defaultTrace('NONE');  # silence all reports

 $folder->defaultTrace('DEBUG');   # Still set as global default!
 $folder->trace('DEBUG');          # local default

=example installing a callback
 Mail::Reporter->defaultTrace

=cut

sub _trace_warn($$$)
{   my ($who, $level, $text) = @_;
    warn "$level: $text\n";
}

sub defaultTrace(;$$)
{   my $thing = shift;

    return ($default_log, $default_trace)
        unless @_;

    my $level = shift;
    my $prio  = $thing->logPriority($level)
        or croak "Unknown trace-level $level.";

    if( ! @_)
    {   $default_log    = $default_trace = $prio;
        $trace_callback = \&_trace_warn;
    }
    elsif(ref $_[0])
    {   $default_log    = $thing->logPriority('NONE');
        $default_trace  = $prio;
        $trace_callback = shift;
    }
    else
    {   $default_log    = $prio;
        $default_trace  = $thing->logPriority(shift);
        $trace_callback = \&_trace_warn;
    }

    ($default_log, $default_trace);
}

__PACKAGE__->defaultTrace('WARNINGS');

#------------------------------------------

=method trace [$level]

Change the trace $level of the object. When no arguments are specified, the
current level is returned only.  It will be returned in one scalar which
contains both the number which is internally used to represent the level,
and the string which represents it.  See M<logPriority()>.

=cut

sub trace(;$$)
{   my $self = shift;

    return $self->logPriority($self->{MR_trace})
        unless @_;

    my $level = shift;
    my $prio  = $levelprio{$level}
        or croak "Unknown trace-level $level.";

    $self->{MR_trace} = $prio;
}

#------------------------------------------

=ci_method log [$level, [$strings]]

As instance method this function has three different purposes.  Without
any argument, it returns one scalar containing the number which is internally
used to represent the current log level, and the textual representation of
the string at the same time. See M<Scalar::Util> method C<dualvar> for
an explanation.

With one argument, a new level of logging detail is set (specify a number
of one of the predefined strings).  With more arguments, it is a report
which may need to be logged or traced.

As class method, only a message can be passed.  The global configuration
value set with M<defaultTrace()> is used to decide whether the message is
shown or ignored.

Each log-entry has a $level and a text string which will
be constructed by joining the $strings.  If there is no newline, it will
be added.

=examples

 print $message->log;      # may print "NOTICE"
 print $message->log +0;   # may print "3"
 $message->log('ERRORS');  # sets a new level, returns the numeric value

 $message->log(WARNING => "This message is too large.");
 $folder ->log(NOTICE  => "Cannot read from file $filename.");
 $manager->log(DEBUG   => "Hi there!", reverse sort @l);

 Mail::Message->log(ERROR => 'Unknown');

=cut

# Implementation detail: the Mail::Box::Parser::C code avoids calls back
# to Perl by checking the trace-level itself.  In the perl code of this
# module however, just always call the log() method, and let it check
# whether or not to display it.

sub log(;$@)
{   my $thing = shift;

    if(ref $thing)   # instance call
    {   return $thing->logPriority($thing->{MR_log})
            unless @_;

        my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level";

        return $thing->{MR_log} = $prio
            unless @_;

        my $text    = join '', @_;
        $trace_callback->($thing, $level, $text)
            if $prio >= $thing->{MR_trace};

        push @{$thing->{MR_report}[$prio]}, $text
            if $prio >= $thing->{MR_log};
    }
    else             # class method
    {   my $level = shift;
        my $prio  = $levelprio{$level}
            or croak "Unknown log-level $level";

        $trace_callback->($thing, $level, join('',@_)) 
           if $prio >= $default_trace;
    }

    $thing;
}


#------------------------------------------

=method report [$level]

Get logged reports, as list of strings.  If a $level is specified, the log
for that level is returned.

In case no $level is specified, you get all messages each as reference
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

=method addReport $object
Add the report from other $object to the report of this object. This is
useful when complex actions use temporary objects which are not returned
to the main application but where the main application would like to know
about any problems.
=cut

sub addReport($)
{   my ($self, $other) = @_;
    my $reports = $other->{MR_report} || return ();

    for(my $prio = 1; $prio < @$reports; $prio++)
    {   push @{$self->{MR_report}[$prio]}, @{$reports->[$prio]}
            if exists $reports->[$prio];
    }
    $self;
}
    
#-------------------------------------------

=method reportAll [$level]

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

Equivalent to

 $folder->report('ERRORS')

=cut

sub errors(@)   {shift->report('ERRORS')}

#-------------------------------------------

=method warnings

Equivalent to

 $folder->report('WARNINGS')

=cut

sub warnings(@) {shift->report('WARNINGS')}

#-------------------------------------------

=method notImplemented

A special case of M<log()>, which logs a C<INTERNAL>-error
and then croaks.  This is used by extension writers.

=error Package $package does not implement $method.

Fatal error: the specific package (or one of its superclasses) does not
implement this method where it should. This message means that some other
related classes do implement this method however the class at hand does
not.  Probably you should investigate this and probably inform the author
of the package.

=cut

sub notImplemented(@)
{   my $self    = shift;
    my $package = ref $self || $self;
    my $sub     = (caller 1)[3];

    $self->log(ERROR => "Package $package does not implement $sub.");
    confess "Please warn the author, this shouldn't happen.";
}

#------------------------------------------

=ci_method logPriority $level

One error level (log or trace) has more than one representation: a
numeric value and one or more strings.  For instance, C<4>, C<'WARNING'>,
and C<'WARNINGS'> are all the same.  You can specify any of these,
and in return you get a dualvar (see M<Scalar::Util> method C<dualvar>)
back, which contains the number and the singular form.

The higher the number, the more important the message.
Only messages about C<INTERNAL> problems are more important than C<NONE>.

=examples

 my $r = Mail::Reporter->logPriority('WARNINGS');
 my $r = Mail::Reporter->logPriority('WARNING');    # same
 my $r = Mail::Reporter->logPriority(4);            # same, deprecated
 print $r;      # prints 'WARNING'  (no S!)
 print $r + 0;  # prints 4
 if($r < Mail::Reporter->logPriority('ERROR')) {..} # true

=cut

sub logPriority($)
{   my $level = $levelprio{$_[1]} or return undef;
    dualvar $level, $levelname[$level];
}

#-------------------------------------------

=method logSettings

Returns a list of C<(key => value)> pairs which can be used to initiate
a new object with the same log-settings as this one.

=examples

 $head->new($folder->logSettings);

=cut

sub logSettings()
{  my $self = shift;
   (log => $self->{MR_log}, trace => $self->{MR_trace});
}

#-------------------------------------------

=method AUTOLOAD

By default, produce a nice warning if the sub-classes cannot resolve
a method.

=cut

sub AUTOLOAD(@)
{   my $thing   = shift;
    our $AUTOLOAD;
    my $class   = ref $thing || $thing;
    (my $method = $AUTOLOAD) =~ s/^.*\:\://;

    $Carp::MaxArgLen=20;
    confess "Method $method() is not defined for a $class.\n";
}

#-------------------------------------------

=section Cleanup
=cut

#-------------------------------------------

=method DESTROY

Cleanup the object.

=cut

sub DESTROY {shift}

1;
