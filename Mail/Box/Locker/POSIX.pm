
use strict;

package Mail::Box::Locker::POSIX;
use base 'Mail::Box::Locker';

use POSIX;
use Fcntl;
use IO::File;
use FileHandle;

=head1 NAME

Mail::Box::Locker::POSIX - lock a folder using kernel file-locking

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

This locker object is created by the folder to get an exclusive lock on
the file which contains the data using the kernel's POSIX facilities.  This
lock is created on a separate file-handle to the folder file, so not the
handle which is reading.  Not all platforms support POSIX locking.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=cut

#-------------------------------------------

=head2 The Locker

=cut

#-------------------------------------------

sub name() {'POSIX'}

#-------------------------------------------

=head2 Locking

=cut

#-------------------------------------------

sub _try_lock($)
{   my ($self, $file) = @_;
    $? = fcntl($file->fileno, F_SETLK, pack('s @256', F_WRLCK)) || 0;
    $?==0;
}

sub _unlock($)
{   my ($self, $file) = @_;
    fcntl($file->fileno, F_SETLK, pack('s @256', F_UNLCK));
    delete $self->{MBL_has_lock};
    $self;
}

#-------------------------------------------

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $filename = $self->filename;

    my $file   = FileHandle->new($filename, 'r+');
    unless(defined $file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    my $end = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};

    while(1)
    {   if($self->_try_lock($file))
        {   $self->{MBL_has_lock}    = 1;
            $self->{MBLF_filehandle} = $file;
            return 1;
        }

        if($? != EAGAIN)
        {   $self->log(ERROR =>
                  "Will never get a lock at ".$self->{MBL_folder}->name.": $!");
            last;
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

#-------------------------------------------

sub isLocked()
{   my $self     = shift;
    my $filename = $self->filename;

    my $file     = FileHandle->new($filename, "r");
    unless($file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    $self->_try_lock($file) or return 0;
    $self->_unlock($file);
    $file->close;

    1;
}

#-------------------------------------------

sub unlock()
{   my $self = shift;

    $self->_unlock(delete $self->{MBLF_filehandle})
       if $self->hasLock;

    $self;
}

#-------------------------------------------

1;
