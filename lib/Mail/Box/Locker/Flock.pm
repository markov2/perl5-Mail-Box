#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::Flock;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Log::Report      'mail-box';

use Fcntl         qw/:DEFAULT :flock/;
use Errno         qw/EAGAIN/;

#--------------------
=chapter NAME

Mail::Box::Locker::Flock - lock a folder using kernel file-locking

=chapter SYNOPSIS

  See the generic Mail::Box::Locker interface

=chapter DESCRIPTION

The C<::Flock> object locks the folder by creating an exclusive lock on
the file using the kernel's C<flock> facilities.  This lock is created
on a separate file-handle to the folder file, so not the handle which
is reading.

File locking does not work in some situations, for instance for
operating systems do not support C<flock>.

=chapter METHODS

=c_method new %options
=default method C<'FLOCK'>

=cut

sub name() {'FLOCK'}

sub _try_lock($)
{	my ($self, $file) = @_;
	flock $file, LOCK_EX|LOCK_NB;
}

sub _unlock($)
{	my ($self, $file) = @_;
	flock $file, LOCK_UN;
	$self;
}

#--------------------
=section Locking

=method lock
Acquire a lock on the folder.

=warning folder $name already flocked.
The $folder is already locked, but you attempt to lock it again.  The
behavior of double flock's is platform dependent, and therefore should
not be attempted.  The second lock is ignored (but the unlock isn't).

=fault unable to open flock file $file for $folder: $!
For C<flock>-ing a $folder it must be opened, which does not succeed for the
specified reason.

=fault will never get a flock at $file for $folder: $!
Tried to C<flock> the $folder, but it did not succeed.  The error code received
from the OS indicates that it will not succeed ever, so we do not need to
try again.

=cut

# 'r+' is require under Solaris and AIX, other OSes are satisfied with 'r'.
my $lockfile_access_mode = ($^O eq 'solaris' || $^O eq 'aix') ? '+<:raw' : '<:raw';

sub lock()
{	my $self   = shift;
	my $folder = $self->folder;

	! $self->hasLock
		or warning(__x"folder {name} already flocked.", name => $folder), return 1;

	my $filename = $self->filename;
	open my $fh, $lockfile_access_mode, $filename
		or fault __x"unable to open flock file {file} for {folder}", file => $filename, folder => $folder;

	my $timeout = $self->timeout;
	my $end     = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;

	while(1)
	{	if($self->_try_lock($fh))
		{	$self->{MBLF_filehandle} = $fh;
			return $self->SUPER::lock;
		}

		$! == EAGAIN
			or fault __x"will never get a flock on {file} for {folder}", file => $filename, folder => $folder;

		--$end or last;
		sleep 1;
	}

	return 0;
}

=method isLocked
=fault unable to check lock file $file for $folder: $!
To check whether the $filename is used to C<flock> a $folder, the file must be
opened.  Apparently this fails, which does not mean that the folder is
locked neither that it is unlocked.

=cut

sub isLocked()
{	my $self     = shift;
	my $filename = $self->filename;

	open my($fh), $lockfile_access_mode, $filename
		or fault __x"unable to check lock file {file} for {folder}", file => $filename, folder => $self->folder;

	$self->_try_lock($fh) or return 0;
	$self->_unlock($fh);
	$fh->close;

	$self->SUPER::unlock;
	1;
}

sub unlock()
{	my $self = shift;

	$self->_unlock(delete $self->{MBLF_filehandle})
		if $self->hasLock;

	$self->SUPER::unlock;
	$self;
}

1;
