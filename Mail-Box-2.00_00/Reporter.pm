
package Mail::Reporter;

$VERSION = '1.319';

# synchronize this with C code in Mail::Box::Parser.
my %trace_levels = (NONE => 6, ERROR => 5, ERRORS => 5, WARNING => 4,
    WARNINGS => 4, PROGRESS => 3, NOTICE => 2, NOTICES => 2, DEBUG => 1);

=head1 NAME

Mail::Reporter - manage errors and trace for  various Mail::* modules

=head1 SYNOPSIS

=head1 DESCRIPTION

Read C<Mail::Box::Manager> first.  There are a few objects which produce
error-messages which will not break the program.  For instance, an erroneous
message doesn't break a whole folder.

This C<Mail::Reporter>-class is the base-class for each object which can
produce errors, and can be configured for each mail-box, mail-message,
and mail-manager seperately.

=head1 METHODS

This is the super-class for all C<Mail::Box> and C<Mail::Message> related
object.  It can store and report messages, and contains the general
constructor.

=over 4

=item new ARGS

This error-container is also the base-constructor for all modules, (as long
as there is no need for an other base object)  The constructor accepts the
following argument about the errors:

=over 4

=item * log =E<gt> LEVEL

Trace messages which have a priority higher or equal to the specified level
are logged into the object's internals and can be retreived later.  The
default log-level is C<WARNINGS>,

Known levels are C<'ERRORS'>, C<'WARNINGS'>, C<'PROGRESS'>, C<'NOTICES'>
C<'DEBUG'>, and C<'NONE'>.  When you specify C<'PROGRESS'>, you will
see each message which is read passing by, and also the warnings and
errors produced while reading.  By the way: C<ERROR> is an alias for C<ERRORS>,
as C<WARNING> is an alias for C<WARNINGS>, and C<NOTICE> for C<NOTICES>.

=item * trace =E<gt> LEVEL

Trace messages which have a level higher or equal to the specified level
are directly printed using warn.  The default trace-level is C<WARNINGS>.

=back

sub new(@) { bless {}, shift)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{ME_log}   = $self->log  ($args->{log} || 'WARNING');
    $self->{ME_trace} = $self->trace($args->{trace} || 'WARNING');
    $self;
}

#------------------------------------------

=item logPriority LEVEL

(instance and class method)   Returns the priority of the named level as
numeric value.  The higher the number, the more important the message.
No message is more important than level C<NONE>.

sub logPriority($) { $trace_levels{$_[1]} }

#------------------------------------------

=item trace [LEVEL]

Change the trace level of the object.

=cut

sub trace(;$)
{   my $self = shift;
    return $self->{MB_trace} unless @_;

    my $level = shift;
    my $prio  = $self->logPriority($level)
        or croak "Unknown trace-level $level.";

    $self->{MB_trace} = $prio;
}

#------------------------------------------

=item log [LEVEL [,STRINGS]]

This method has three uses.  Without any argument, it returns the name
of the current log level.  With one argument, a new level of logging
detail is set.  With more arguments, it is a report which may need to be
logged or traced.

Each log-entry has a LEVEL (see above), and a text which will
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
    return $self->{MB_trace} unless @_;

    my $level = shift;
    my $prio  = $trace_level{$level}
        or croak "Unknown trace-level $level.";

    return $self->{MB_trace} = $prio unless @_;

    my $text    = join '', @_;
    $text      .= $message ? " in message $msgnr" : '';
    $text      .= "\n" unless (substr $text, -1) eq "\n";

    warn "$level: $text" if $level <= $self->{MB_trace};

    push @{$self->{report}[$level]}, $text;
    $self;
}

#------------------------------------------

=item report [LEVEL]

Get logged reports.  In case there is a LEVEL specified, you get each
message with exactly that level, as list of strings.

In case no LEVEL is specified, you get all messages each as reference
to a tuple with level and message.

Examples:

   my @warns = $message->report('WARNINGS');
      # previous indirectly callable with
      my @warns = $msg->warnings;

   print $folder->report('ERRORS');

   if($folder->report('TRACE')) {...}

   my @reports = $folder->report;
   foreach (@reports) {
       my ($level, $text) = @$_;
       print "$level report: $text";
   }

=cut

sub report(;$)
{   my $self   = shift;

    my $reports = $self->{ME_report} || return ();

    if(@_)
    {   my $level = shift;
        my $prio  = $trace_levels{$level}
            or croak "Unknown report level $level.";

        return $reports->[$prio] ? @{$reports->[$prio]} : ();
    }

    push @reports;
    for(my $prio = 0; $prio < @$reports; $prio++)
    {   next unless $reports->[$prio];
        my $level = $levelname{$prio};
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
{
}

#-------------------------------------------

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.319

=cut

1;
