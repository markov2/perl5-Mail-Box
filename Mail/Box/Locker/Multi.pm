
use strict;

package Mail::Box::Locker::Multi;
use base 'Mail::Box::Locker';

use IO::File;
use Carp;

=head1 NAME

Mail::Box::Locker::Multi - lock a folder in all ways which work

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::Multi> locker locks a folder in each way it can.  This way, the
chance is highest that any other program will leave the folder alone
during our access to it.

NFS-lock and Flock are tried.  More may be added when the ways to
lock are extended.  DotLock overlaps with NFS-lock, but NFS-lock is
safer, so that version is preferred.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=option  use ARRAY
=default use <all possible>

Array of locker types and locker objects to be used to lock one
folder.  The type names are converted into objects.

Some locking types are not available on some platforms, so they will
not be excluded from the default list (NFS POSIX Flock).

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my @use
     = exists $args->{use} ? @{$args->{use}}
     : $^O =~ m/mswin/i    ? qw/    POSIX Flock/
     :                       qw/NFS POSIX Flock/;

    my (@lockers, @used);

    foreach my $method (@use)
    {   my $locker = eval
        {   Mail::Box::Locker->new
              ( %$args
              , method  => $method
              , timeout => 1
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

=head2 The Locker

=cut

#-------------------------------------------

sub name() {'MULTI'}

#-------------------------------------------

=method lockers

Returns a list with all locker objects used by this object.

=cut

sub lockers() { @{shift->{MBLM_lockers}} }

#-------------------------------------------

=head2 Locking

=cut

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

    while(1)
    {   return $self->{MBL_has_lock} = 1
            if $self->_try_lock;

        last unless --$end;
        sleep 1;
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

1;
