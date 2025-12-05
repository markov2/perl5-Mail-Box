#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Locker::DotLock;
use parent 'Mail::Box::Locker';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error fault warning/ ];

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

=method folder 
=error Dotlock requires a lock file name.
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
		  :    error __x"Dotlock requires a lock file name.";

		$self->filename($filename);
	}

	$self->SUPER::folder($folder);
}

#--------------------
=section Locking

=method lock $file
=fault lockfile $file can never be created: $!
=cut

sub _try_lock($)
{	my ($self, $lockfile) = @_;
	return if -e $lockfile;

	my $flags = $^O eq 'MSWin32' ?  O_CREAT|O_EXCL|O_WRONLY :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;
	my $lock;
	sysopen $lock, $lockfile, $flags, 0600
		and $lock->close, return 1;

	$! == EEXIST
		or fault __x"lockfile {file} can never be created", file => $lockfile;

	1;
}

=method unlock
=warning couldn't remove lockfile $file: $!
=cut

sub unlock()
{	my $self = shift;
	$self->hasLock
		or return $self;

	my $lock = $self->filename;

	unlink $lock
		or warning __x"couldn't remove lockfile {file}: {rc}", file => $lock, rc => $!;

	$self->SUPER::unlock;
	$self;
}

=method lock
=warning folder already locked with file $file
=warning removed expired lockfile $file
=fault failed to remove expired lockfile $file: $!
=cut

sub lock()
{	my $self   = shift;

	my $lockfile = $self->filename;
	$self->hasLock
		and warning(__x"folder already locked with file {file}.", file => $lockfile), return 1;

	my $timeout  = $self->timeout;
	my $end      = $timeout eq 'NOTIMEOUT' ? -1 : $timeout;
	my $expire   = $self->expires/86400;  # in days for -A

	while(1)
	{
		return $self->SUPER::lock
			if $self->_try_lock($lockfile);

		if(-e $lockfile && -A $lockfile > $expire)
		{	unlink $lockfile
				or fault __x"failed to remove expired lockfile {file}", file => $lockfile;

			warning __x"removed expired lockfile {file}.", file => $lockfile;
			redo;
		}

		--$end or last;
		sleep 1;
	}

	return 0;
}

sub isLocked() { -e shift->filename }

1;
