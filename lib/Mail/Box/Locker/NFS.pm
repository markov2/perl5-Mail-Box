#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::NFS;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Log::Report      'mail-box';

use Sys::Hostname    qw/hostname/;
use Fcntl            qw/O_CREAT O_WRONLY/;

#--------------------
=chapter NAME

Mail::Box::Locker::NFS - lock a folder with a separate file, NFS-safe

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

Like the C<::DotLock> locker, but then in an NFS-safe fashion.  Over NFS,
the creation of a file is not atomic.  The C<::DotLock> locker depends
on an atomic C<open> system call, hence in not usable to lock a folder
which accessed over NFS.  The C<::NFS>
locker is therefore more complicated (so therefore slower), but will work
for NFS --and for local disks as well.

=chapter METHODS

=c_method new %options

=default method C<'NFS'>
=cut

sub name() { 'NFS' }

#--------------------
=section Locking
=cut

# METHOD nfs
# This hack is copied from the Mail::Folder packages, as written
# by Kevin Jones.  Cited from his code:
#    Whhheeeee!!!!!
#    In NFS, the O_CREAT|O_EXCL isn't guaranteed to be atomic.
#    So we create a temp file that is probably unique in space
#    and time ($folder.lock.$time.$pid.$host).
#    Then we use link to create the real lock file. Since link
#    is atomic across nfs, this works.
#    It loses if it's on a filesystem that doesn't do long filenames.

my $hostname = hostname;

sub _tmpfilename()
{	my $self = shift;
	$self->{MBLN_tmp} ||= $self->filename . $$;
}

sub _construct_tmpfile()
{	my $self    = shift;
	my $tmpfile = $self->_tmpfilename;

	sysopen my $fh, $tmpfile, O_CREAT|O_WRONLY, 0600
		or return undef;

	$fh->close;
	$tmpfile;
}

sub _try_lock($$)
{	my ($self, $tmpfile, $lockfile) = @_;

	link $tmpfile, $lockfile
		or return undef;

	my $linkcount = (stat $tmpfile)[3];

	unlink $tmpfile;
	$linkcount == 2;
}

=method lock

=warning folder $name already locked over NFS.
Do not try to lock the folder when the application already has the
lock: it will give you dead-locks.

=warning removed expired lockfile $file.
A lock $file was found which was older than the expiration period as
specified with M<new(timeout)>.  The lock file was successfully
removed.

=fault unable to remove expired lockfile $file: $!
A lock file was found which was older than the expiration period as
specified with the M<new(timeout)> option.  It is impossible to remove that
lock file, so we need to wait until it vanishes by some external cause.

=cut

sub lock()
{	my $self     = shift;
	my $folder   = $self->folder;

	$self->hasLock
		and warning(__x"folder {name} already locked over NFS.", name => $folder), return 1;

	my $lockfile = $self->filename;
	my $tmpfile  = $self->_construct_tmpfile or return;
	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;
	my $expires  = $self->expires / 86400;  # in days for -A

	if(-e $lockfile && -A $lockfile > $expires)
	{	unlink $lockfile
			or fault __x"Unable to remove expired lockfile {file}", file => $lockfile;

		warning __x"removed expired lockfile {file}.", file => $lockfile;
	}

	while(1)
	{	return $self->SUPER::lock
			if $self->_try_lock($tmpfile, $lockfile);

		--$end or last;
		sleep 1;
	}

	return 0;
}

sub isLocked()
{	my $self     = shift;
	my $tmpfile  = $self->_construct_tmpfile or return 0;
	my $lockfile = $self->filename;

	my $fh = $self->_try_lock($tmpfile, $lockfile) or return 0;
	close $fh;

	$self->_unlock($tmpfile, $lockfile);
	$self->SUPER::unlock;

	1;
}

=method unlock
=fault couldn't remove lockfile $file: $!
=cut

sub _unlock($$)
{	my ($self, $tmpfile, $lockfile) = @_;

	unlink $lockfile
		or fault __x"couldn't remove lockfile {file}", file => $lockfile;

	unlink $tmpfile;
	$self;
}

sub unlock($)
{	my $self   = shift;
	$self->hasLock or return $self;

	$self->_unlock($self->_tmpfilename, $self->filename);
	$self->SUPER::unlock;
	$self;
}

1;
