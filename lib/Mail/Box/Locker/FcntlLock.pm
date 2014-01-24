
use strict;

package Mail::Box::Locker::FcntlLock;
use base 'Mail::Box::Locker';

use Fcntl;
use IO::File;
use Errno   qw/EAGAIN/;
use File::FcntlLock;


=chapter NAME

Mail::Box::Locker::FcntlLock - lock a folder using File::FcntlLock

=chapter SYNOPSIS

 See M<Mail::Box::Locker>

=chapter DESCRIPTION

This locker object is uses M<File::FcntlLock>, and was contributed by
Jim in Aus. It is close to M<Mail::Box::Locker::POSIX>, but does work
on more systems, for instance Darwin.

You will need to install M<File::FcntlLock> separately: there is no
dependency to it by the MailBox distribution.

=chapter METHODS

=c_method new %options

=default method C<FcntlLock>

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{file} = $args->{posix_file} if $args->{posix_file};
    $self->SUPER::init($args);
}

sub name() {'FcntlLock'}

sub _try_lock($)
{   my ($self, $file) = @_;
    my $fl = File::FcntlLock->new;
    $fl->l_type(F_WRLCK);
    $? = $fl->lock($file, F_SETLK);
    $?==0;
}

sub _unlock($)
{   my ($self, $file) = @_;
    my $fl = File::FcntlLock->new;
    $fl->l_type(F_UNLCK);
    $fl->lock($file, F_SETLK);
    delete $self->{MBL_has_lock};
    $self;
}

=method lock

=warning Folder $folder already lockf'd

=error Unable to open FcntlLock lock file $filename for $folder: $!
For FcntlLock style locking, a folder it must be opened, which does not
succeed for the specified reason.

=error Will never get a FcntlLock lock at $filename for $folder: $!
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
           "Unable to open FcntlLock lock file $filename for $folder: $!");
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
            "Will never get a FcntlLock lock on $filename for $self->{MBL_folder}: $!");
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
