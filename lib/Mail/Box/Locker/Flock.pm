#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::Flock;
use base 'Mail::Box::Locker';

use strict;
use warnings;

use IO::File;
use Fcntl         qw/:DEFAULT :flock/;
use Errno         qw/EAGAIN/;

#--------------------
=chapter NAME

Mail::Box::Locker::Flock - lock a folder using kernel file-locking

=chapter SYNOPSIS

  See Mail::Box::Locker

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


=method lock

=warning Folder $folder already flocked
The folder is already locked, but you attempt to lock it again.  The
behavior of double flock's is platform dependent, and therefore should
not be attempted.  The second lock is ignored (but the unlock isn't)

=error Unable to open flock file $filename for $folder: $!
For flock-ing a folder it must be opened, which does not succeed for the
specified reason.

=error Will never get a flock at $filename for $folder: $!
Tried to flock the folder, but it did not succeed.  The error code received
from the OS indicates that it will not succeed ever, so we do not need to
try again.

=cut

# 'r+' is require under Solaris and AIX, other OSes are satisfied with 'r'.
my $lockfile_access_mode = ($^O eq 'solaris' || $^O eq 'aix') ? 'r+' : 'r';

sub lock()
{	my $self   = shift;
	my $folder = $self->folder;

	if($self->hasLock)
	{	$self->log(WARNING => "Folder $folder already flocked.");
		return 1;
	}

	my $filename = $self->filename;
	my $file      = IO::File->new($filename, $lockfile_access_mode);
	unless($file)
	{	$self->log(ERROR => "Unable to open flock file $filename for $folder: $!");
		return 0;
	}

	my $timeout = $self->timeout;
	my $end     = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;

	while(1)
	{	if($self->_try_lock($file))
		{	$self->{MBLF_filehandle} = $file;
			return $self->SUPER::lock;
		}

		if($! != EAGAIN)
		{	$self->log(ERROR => "Will never get a flock on $filename for $folder: $!");
			last;
		}

		last unless --$end;
		sleep 1;
	}

	return 0;
}

=method isLocked
=error Unable to check lock file $filename for $folder: $!
To check whether the filename is used to flock a folder, the file must be
opened.  Apparently this fails, which does not mean that the folder is
locked neither that it is unlocked.

=cut

sub isLocked()
{	my $self     = shift;
	my $filename = $self->filename;

	my $file     = IO::File->new($filename, $lockfile_access_mode);
	unless($file)
	{	my $folder = $self->folder;
		$self->log(ERROR =>
			"Unable to check lock file $filename for $folder: $!");
		return 0;
	}

	$self->_try_lock($file) or return 0;
	$self->_unlock($file);
	$file->close;

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
