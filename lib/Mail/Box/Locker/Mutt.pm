#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::Mutt;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use POSIX      qw/sys_wait_h/;

#--------------------
=chapter NAME

Mail::Box::Locker::Mutt - lock a folder using mutt_dotlock

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

The C<mutt> email reader includes a separate program which is specialized
in locking folders.  This locker class uses this external program.
Mutt is not automatically installed.

=chapter METHODS

=c_method new %options
=option  exe PATH
=default exe C<mutt_dotlock>
The name of the program.  May be a relative or absolute path.
=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);

	$self->{MBLM_exe} = $args->{exe} || 'mutt_dotlock';
	$self;
}

sub name()     { 'MUTT' }
sub lockfile() { $_[0]->filename . '.lock' }

#--------------------
=section Attributes
=method exe
Returns the name of the external binary.
=cut

sub exe() { $_[0]->{MBLM_exe} }

=method unlock
=warning Couldn't remove mutt-unlock $folder: $!
=cut

sub unlock()
{	my $self = shift;
	$self->hasLock or return $self;

	unless(system $self->exe, '-u', $self->filename)
	{	my $folder = $self->folder;
		$self->log(WARNING => "Couldn't remove mutt-unlock $folder: $!");
	}

	$self->SUPER::unlock;
	$self;
}

#--------------------
=section Locking

=method lock
=warning Folder $folder already mutt-locked
=warning Removed expired mutt-lock $lockfile
=error Failed to remove expired mutt-lock $lockfile: $!
=cut

sub lock()
{	my $self     = shift;
	my $folder   = $self->folder;

	$self->hasLock
		and $self->log(WARNING => "Folder $folder already mutt-locked"), return 1;

	my $filename = $self->filename;
	my $lockfn   = $self->lockfile;

	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;
	my $expire   = $self->expires / 86400;  # in days for -A
	my $exe      = $self->exe;

	while(1)
	{
		system $exe, '-p', '-r', 1, $filename
			or return $self->SUPER::lock;

		WIFEXITED($?) && WEXITSTATUS($?)==3
			or $self->log(ERROR => "Will never get a mutt-lock: $!"), return 0;

		if(-e $lockfn && -A $lockfn > $expire)
		{	system $exe, '-f', '-u', $filename
				and $self->log(WARNING => "Removed expired mutt-lock $lockfn"), redo;

			$self->log(ERROR => "Failed to remove expired mutt-lock $lockfn: $!");
			last;
		}

		--$end or last;
		sleep 1;
	}

	0;
}

sub isLocked()
{	my $self     = shift;
	system $self->exe, '-t', $self->filename;
	WIFEXITED($?) && WEXITSTATUS($?)==3;
}

1;
