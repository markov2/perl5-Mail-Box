#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::FcntlLock;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use File::FcntlLock  ();
use Fcntl            qw/F_WRLCK F_SETLK F_UNLCK/;
use Errno            qw/EAGAIN/;

#--------------------
=chapter NAME

Mail::Box::Locker::FcntlLock - lock a folder using File::FcntlLock

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

This locker object is uses File::FcntlLock, and was contributed by
Jim in Aus. It is close to Mail::Box::Locker::POSIX, but does work
on more systems, for instance Darwin.

You will need to install File::FcntlLock separately: there is no
dependency to it by the MailBox distribution.

=chapter METHODS

=c_method new %options
=default method C<FcntlLock>
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{file} = $args->{posix_file} if $args->{posix_file};
	$self->SUPER::init($args);
}

sub name() { 'FcntlLock' }

#--------------------
=section Locking
=cut

sub _try_lock($)
{	my ($self, $file) = @_;
	my $fl = File::FcntlLock->new;
	$fl->l_type(F_WRLCK);
	$? = $fl->lock($file, F_SETLK);
	$?==0;
}

sub _unlock($)
{	my ($self, $file) = @_;
	my $fl = File::FcntlLock->new;
	$fl->l_type(F_UNLCK);
	$fl->lock($file, F_SETLK);
	$self;
}

=method lock

=warning Folder $folder already lockf'd

=error Unable to open FcntlLock lock file $file for $folder: $!
For FcntlLock style locking, a $folder it must be opened, which does not
succeed for the specified reason.

=error Will never get a FcntlLock lock at $file for $folder: $!
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

	my $file = $self->filename;
	open my $fh, '+<:raw', $file;
	unless(defined $fh)
	{	my $folder = $self->folder;
		$self->log(ERROR => "Unable to open FcntlLock lock file $file for $folder: $!");
		return 0;
	}

	my $timeout = $self->timeout;
	my $end     = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;

	while(1)
	{	if($self->_try_lock($fh))
		{	$self->SUPER::lock;
			$self->{MBLF_filehandle} = $fh;
			return 1;
		}

		unless($!==EAGAIN)
		{	my $folder = $self->folder;
			$self->log(ERROR => "Will never get a FcntlLock lock on $file for $folder: $!");
			last;
		}

		--$end or last;
		sleep 1;
	}

	return 0;
}

=method isLocked

=error Unable to check lock file $file for $folder: $!
To check whether the filename is used to flock a folder, the file must be
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
