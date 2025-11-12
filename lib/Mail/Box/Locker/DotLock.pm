#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::DotLock;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Carp;
use File::Spec::Functions qw/catfile/;
use Errno                 qw/EEXIST/;
use Fcntl                 qw/O_CREAT O_EXCL O_WRONLY O_NONBLOCK/;

#--------------------
=chapter NAME

Mail::Box::Locker::DotLock - lock a folder with a separate file

=chapter SYNOPSIS

  See Mail::Box::Locker

=chapter DESCRIPTION

The C<::DotLock> object lock the folder by creating a file with the
same name as the folder, extended by C<.lock>.

=chapter METHODS

=c_method new %options

=default file <folderfile>C<.lock>
Name of the file to lock.  By default, the folder's name is extended
with C<.lock>.

=option  dotlock_file $file
=default dotlock_file undef
Alternative name for P<file>, especially useful to confusion when
the multi locker is used.
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{file} = $args->{dotlock_file} if $args->{dotlock_file};
	$self->SUPER::init($args);
}

sub name() { 'DOTLOCK' }

#--------------------
=section Attributes
=cut

sub folder(;$)
{	my $self = shift;
	@_ && $_[0] or return $self->SUPER::folder;

	my $folder = shift;
	unless(defined $self->filename)
	{	my $org = $folder->organization;

		my $filename
		  = $org eq 'FILE'     ? $folder->filename . '.lock'
		  : $org eq 'DIRECTORY'? catfile($folder->directory, '.lock')
		  :    croak "Need lock file name for DotLock.";

		$self->filename($filename);
	}

	$self->SUPER::folder($folder);
}

#--------------------
=section Locking
=cut

sub _try_lock($)
{	my ($self, $lockfile) = @_;
	return if -e $lockfile;

	my $flags = $^O eq 'MSWin32' ?  O_CREAT|O_EXCL|O_WRONLY :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;
	my $lock;
	sysopen $lock, $lockfile, $flags, 0600
		and $lock->close, return 1;

	$! == EEXIST
		or $self->log(ERROR => "lockfile $lockfile can never be created: $!"), return 0;

	1;
}

=method unlock
=warning Couldn't remove lockfile $lock: $!
=cut

sub unlock()
{	my $self = shift;
	$self->hasLock
		or return $self;

	my $lock = $self->filename;

	unlink $lock
		or $self->log(WARNING => "Couldn't remove lockfile $lock: $!");

	$self->SUPER::unlock;
	$self;
}

=method lock
=warning Folder already locked with file $lockfile
=warning Removed expired lockfile $lockfile
=error Failed to remove expired lockfile $lockfile: $!
=cut

sub lock()
{	my $self   = shift;

	my $lockfile = $self->filename;
	$self->hasLock
		and $self->log(WARNING => "Folder already locked with file $lockfile"), return 1;

	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;
	my $expire   = $self->expires/86400;  # in days for -A

	while(1)
	{
		return $self->SUPER::lock
			if $self->_try_lock($lockfile);

		if(-e $lockfile && -A $lockfile > $expire)
		{	unlink $lockfile
				or $self->log(ERROR => "Failed to remove expired lockfile $lockfile: $!"), last;

			$self->log(WARNING => "Removed expired lockfile $lockfile");
			redo;
		}

		last unless --$end;
		sleep 1;
	}

	return 0;
}

sub isLocked() { -e shift->filename }

1;
