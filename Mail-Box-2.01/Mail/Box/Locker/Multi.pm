
use strict;

package Mail::Box::Locker::Multi;
use base 'Mail::Box::Locker';

use IO::File;
use Carp;

=head1 NAME

Mail::Box::Locker::Multi - lock a folder in all ways which work

=head1 CLASS HIERARCHY

 Mail::Box::Locker::Multi
 is a Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::Multi> locker locks a folder in each way it can.  This way, the
chance is highest that any other program will leave the folder alone
during our access to it.

NFS-lock and Flock are tried.  More may be added when the ways to
lock are extended.  DotLock overlaps with NFS-lock, but NFS-lock is
safer, so that version is prefered.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Box::Locker> (MBL).

The general methods for C<Mail::Box::Locker::Multi> objects:

  MBL DESTROY                          MBL name
   MR errors                               new OPTIONS
  MBL filename                          MR report [LEVEL]
  MBL hasLock                           MR reportAll [LEVEL]
  MBL isLocked                          MR trace [LEVEL]
  MBL lock FOLDER                      MBL unlock
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#-------------------------------------------

sub name() {'MULTI'}

#-------------------------------------------

=item new OPTIONS

 OPTIONS        DESCRIBED IN               DEFAULT
 file           Mail::Box::Locker          undef
 log            Mail::Reporter             'WARNINGS'
 method         Mail::Box::Locker          <not used>
 timeout        Mail::Box::Locker          1 hour
 trace          Mail::Reporter             'WARNINGS'
 wait           Mail::Box::Locker          10 seconds
 use            Mail::Box::Locker::Multi   [ 'NFS', 'POSIX', 'Flock' ]

=over 4

=item * use =E<gt> ARRAY

Array of locker types and locker objects to be used.  All types are
converted into objects.

=over

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my @use = exists $args->{use} ? @{$args->{use}} : qw/NFS POSIX Flock/;
    my (@lockers, @used);

    foreach my $method (@use)
    {   my $locker = eval
        {   Mail::Box::Locker->new
              ( %$args
              , method  => $method
              , wait    => 1
              )
        };
        next unless defined $locker;

        push @lockers, $locker;
        push @used, $method;
    }

    $self->{MBLM_lockers} = \@lockers;
    $self->log(PROGRESS => "Multi-locking via @used.");
    $self;
}

#-------------------------------------------

=item lockers

Returns a list with all locker objects used by this object.

=cut

sub lockers() { @{shift->{MBLM_lockers}} }

#-------------------------------------------

sub _try_lock($)
{   my $self     = shift;
    my @successes;

    foreach my $locker ($self->lockers)
    {
        unless($locker->lock)
        {   $_->unlock foreach @successes;
            return 0;
        }
        push @successes, $locker;
    }

    1;
}

#-------------------------------------------

sub unlock()
{   my $self = shift;
    return $self unless $self->{MBL_has_lock};

    $_->unlock foreach $self->lockers;
    delete $self->{MBL_has_lock};

    $self;
}

#-------------------------------------------

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};
    my $timer = 0;

    while($timer < $end)
    {   return $self->{MBL_has_lock} = 1 if $self->_try_lock;
        $timer++;
    }

    return 0;
}

#-------------------------------------------

sub isLocked()
{   my $self     = shift;
    $self->_try_lock($self->filename) or return 0;
    $self->unlock;
    1;
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

This code is beta, version 2.010.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
