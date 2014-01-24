
use strict;

package Mail::Box::Locker::POSIX;
use base 'Mail::Box::Locker';

use Fcntl;
use IO::File;
use Errno   qw/EAGAIN/;

=chapter NAME

Mail::Box::Locker::POSIX - lock a folder using kernel file-locking

=chapter SYNOPSIS

 See M<Mail::Box::Locker>

=chapter DESCRIPTION

This locker object is created by the folder to get an exclusive lock on
the file which contains the data using the kernel's POSIX facilities.  This
lock is created on a separate file-handle to the folder file, so not the
handle which is reading.  Not all platforms support POSIX locking.

=chapter METHODS

=c_method new %options

=default method C<POSIX>

=option  posix_file FILENAME
=default posix_file <undef>
Alternative name for C<file>, especially useful to avoid confusion
when the multi-locker is used.
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{file} = $args->{posix_file} if $args->{posix_file};
    $self->SUPER::init($args);
}

sub name() {'POSIX'}

sub _try_lock($)
{   my ($self, $file) = @_;
    $? = fcntl($file, F_SETLK, pack('s @256', F_WRLCK)) || ($!+0);
    $?==0;
}

sub _unlock($)
{   my ($self, $file) = @_;
    fcntl($file, F_SETLK, pack('s @256', F_UNLCK));
    delete $self->{MBL_has_lock};
    $self;
}

=method lock

=warning Folder $folder already lockf'd

=error Unable to open POSIX lock file $filename for $folder: $!
For POSIX style locking, a folder it must be opened, which does not
succeed for the specified reason.

=error Will never get a POSIX lock at $filename for $folder: $!
Tried to lock the folder, but it did not succeed.  The error code received
from the OS indicates that it will not succeed ever, so we do not need to
try again.

=cut

sub lock()
{   my $self   = shift;

    if($self->hasLock)
    {   my $folder = $self->folder;
        $self->log(WARNING => "Folder $folder already lockf'd");
        return 1;
    }

    my $filename = $self->filename;

    my $file   = IO::File->new($filename, 'r+');
    unless(defined $file)
    {   my $folder = $self->folder;
        $self->log(ERROR =>
           "Unable to open POSIX lock file $filename for $folder: $!");
        return 0;
    }

    my $end = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};

    while(1)
    {   if($self->_try_lock($file))
        {   $self->{MBL_has_lock}    = 1;
            $self->{MBLF_filehandle} = $file;
            return 1;
        }

        unless($!==EAGAIN)
        {   $self->log(ERROR =>
            "Will never get a POSIX lock on $filename for $self->{MBL_folder}: $!");
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
{   my $self     = shift;
    my $filename = $self->filename;

    my $file     = IO::File->new($filename, "r");
    unless($file)
    {   $self->log(ERROR =>
               "Unable to check lock file $filename for $self->{MBL_folder}: $!");
        return 0;
    }

    $self->_try_lock($file)==0 or return 0;
    $self->_unlock($file);
    $file->close;
    1;
}

sub unlock()
{   my $self = shift;

    $self->_unlock(delete $self->{MBLF_filehandle})
       if $self->hasLock;

    $self;
}

1;
