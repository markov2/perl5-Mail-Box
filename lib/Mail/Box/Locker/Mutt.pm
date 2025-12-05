#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::Mutt;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x fault warning/ ];

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

sub exe()      { $_[0]->{MBLM_exe} }

#--------------------
=section Locking

=method unlock
=warning couldn't remove mutt-unlock $folder: $!
=cut

sub unlock()
{	my $self = shift;
	$self->hasLock or return $self;

	system $self->exe, '-u', $self->filename
		and warning __x"couldn't remove mutt-unlock {folder}", folder => $self->folder;

	$self->SUPER::unlock;
	$self;
}

=method lock
=warning folder $name already mutt-locked with $file.
=fault   folder $name will never get a mutt-lock with $file: $!
=warning removed expired mutt-lock file $file.
=fault   failed to remove expired mutt-lock $file: $!
=cut

sub lock()
{	my $self     = shift;
	my $filename = $self->filename;

	$self->hasLock
		and warning(__x"folder {name} already mutt-locked with {file}.", name => $self->folder, file => $filename), return 1;

	my $lockfn   = $self->lockfile;

	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;
	my $expire   = $self->expires / 86400;  # in days for -A
	my $exe      = $self->exe;

	while(1)
	{
		system $exe, '-p', '-r', 1, $filename
			or return $self->SUPER::lock;   # success

		WIFEXITED($?) && WEXITSTATUS($?)==3
			or fault __x"folder {name} will never get a mutt-lock with {file}", name => $self->folder, file => $filename;

		if(-e $lockfn && -A $lockfn > $expire)
		{	system $exe, '-f', '-u', $filename
				and warning(__x"removed expired mutt-lock file {file}.", file => $lockfn), redo;

			fault __x"failed to remove expired mutt-lock {file}", file => $lockfn;
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
