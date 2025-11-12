#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::Multi;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Carp;
use Scalar::Util   qw/blessed/;

#--------------------
=chapter NAME

Mail::Box::Locker::Multi - lock a folder in all ways which work

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

The C<::Multi> locker locks a folder in each way it can.  This way, the
chance is highest that any other program will leave the folder alone
during our access to it.

NFS-lock and Flock are tried.  More may be added when the ways to
lock are extended.  DotLock overlaps with NFS-lock, but NFS-lock is
safer, so that version is preferred.

=chapter METHODS

=c_method new %options
You may also pass all %options understood by the initiated lockers
used by the multi locker.

=default method C<'MULTI'>

=option  use ARRAY-of-(NAMES|LOCKER)
=default use <all possible>
Array of locker type NAMES or LOCKER objects to be used to lock one
folder.  The type NAMES are converted into objects.  When you create your
own LOCKER objects, be sure to set the timeout very short (preferably
to 1).

Some locking types are not available on some platforms, so they will
not be excluded from the default list (NFS POSIX Flock).

=example using a subset of multi-lockers
  my $locker = Mail::Box::Locker::Multi->new(use => ['DOTLOCK','FLOCK']);

=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);

	my @use
	  = exists $args->{use} ? @{delete $args->{use}}
	  : $^O eq 'MSWin32'    ? qw/Flock/
	  :   qw/NFS FcntlLock Flock/;

	my (@lockers, @used);

	foreach my $method (@use)
	{	if(blessed $method && $method->isa('Mail::Box::Locker'))
		{	push @lockers, $method;
			push @used, ref $method =~ s/.*\:\://r;
			next;
		}

		my $locker = eval {	Mail::Box::Locker->new(%$args, method => $method, timeout => 1) };
		defined $locker or next;

		push @lockers, $locker;
		push @used, $method;
	}

	$self->{MBLM_lockers} = \@lockers;
	$self->log(PROGRESS => "Multi-locking via @used.");
	$self;
}

#--------------------
=section Attributes

=method lockers
Returns a list with all locker objects used by this object.
=cut

sub lockers() { @{ $_[0]->{MBLM_lockers}} }

sub name() {'MULTI'}

sub _try_lock()
{	my $self     = shift;
	my @successes;

	foreach my $locker ($self->lockers)
	{
		unless($locker->lock)
		{	$_->unlock for @successes;
			return 0;
		}
		push @successes, $locker;
	}

	1;
}

#--------------------
=section Locking
=cut

sub unlock()
{	my $self = shift;
	$self->hasLock or return $self;
	$_->unlock for $self->lockers;
	$self->SUPER::unlock;
	$self;
}

sub lock()
{	my $self  = shift;
	return 1 if $self->hasLock;

	my $timeout = $self->timeout;
	my $end     = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;

	while(1)
	{	return $self->SUPER::lock
			if $self->_try_lock;

		last unless --$end;
		sleep 1;
	}

	return 0;
}

sub isLocked()
{	my $self     = shift;

	# Try get a lock
	$self->_try_lock or return 0;

	# and release it immediately
	$self->unlock;
	1;
}


1;
