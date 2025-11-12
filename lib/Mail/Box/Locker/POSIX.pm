#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::POSIX;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Fcntl   qw/F_WRLCK F_UNLCK F_SETLK/;
use Errno   qw/EAGAIN/;

# fcntl() should not be used without XS: the below is sensitive
# for changes in the structure.  However, at the moment it seems
# there are only two options: either SysV-style or BSD-style

my $pack_pattern = $^O =~ /bsd|darwin/i ? '@20 s @256' : 's @256';

#--------------------
=chapter NAME

Mail::Box::Locker::POSIX - lock a folder using kernel file-locking

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

This locker object is created by the folder to get an exclusive lock on
the file which contains the data using the kernel's POSIX facilities.  This
lock is created on a separate file-handle to the folder file, so not the
handle which is reading.

B<WARNING>: Not all platforms support POSIX locking (via fcntl) and not
always in the same way.  This implementation does not use XS to access
the structure of fcntl(): it is better to use the ::FcntlLock which does.
No, this implementation "guesses" the location of the bytes.

=chapter METHODS

=c_method new %options

=default method C<POSIX>

=option  posix_file FILENAME
=default posix_file <undef>
Alternative name for C<file>, especially useful to avoid confusion
when the multi-locker is used.
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{file} = $args->{posix_file} if $args->{posix_file};
	$self->SUPER::init($args);
}

sub name() { 'POSIX' }

#--------------------
=section Locking
=cut

sub _try_lock($)
{	my ($self, $file) = @_;
	my $p = pack $pack_pattern, F_WRLCK;
	$? = fcntl($file, F_SETLK, $p) || ($!+0);
	$?==0;
}

sub _unlock($)
{	my ($self, $file) = @_;
	my $p = pack $pack_pattern, F_UNLCK;
	fcntl $file, F_SETLK, $p;
	$self;
}

=method lock

=warning Folder $folder already lockf'd

=error Unable to open POSIX lock file $file for $folder: $!
For POSIX style locking, a $folder it must be opened, which does not
succeed for the specified reason.

=error Will never get a POSIX lock at $file for $folder: $!
Tried to lock the $folder, but it did not succeed.  The error code received
from the OS indicates that it will not succeed ever, so we do not need to
try again.

=cut

sub lock()
{	my $self   = shift;

	if($self->hasLock)
	{	my $folder = $self->folder;
		$self->log(WARNING => "Folder $folder already lockf'd");
		return 1;
	}

	my $file     = $self->filename;
	my $folder   = $self->folder;

	open my $fh, '+<:raw', $file
		or $self->log(ERROR => "Unable to open POSIX lock file $file for $folder: $!"), return 0;

	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;

	while(1)
	{	if($self->_try_lock($fh))
		{	$self->{MBLF_filehandle} = $fh;
			return $self->SUPER::lock;
		}

		$!==EAGAIN
			or $self->log(ERROR => "Will never get a POSIX lock on $file for $folder: $!"), return 0;

		--$end or last;
		sleep 1;
	}

	return 0;
}

=method isLocked

=error Unable to check lock file $file for $folder: $!
To check whether the $file is used to flock a $folder, the file must be
opened.  Apparently this fails, which does not mean that the folder is
locked neither that it is unlocked.
=cut

sub isLocked()
{	my $self = shift;
	my $file = $self->filename;

	open my $fh, '<:raw', $file;
	unless($fh)
	{	my $folder = $self->folder;
		$self->log(ERROR => "Unable to check lock file $file for $folder: $!");
		return 0;
	}

	$self->_try_lock($fh)==0 or return 0;
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
