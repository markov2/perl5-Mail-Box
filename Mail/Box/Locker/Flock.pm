
use strict;

package Mail::Box::Locker::Flock;
use base 'Mail::Box::Locker';

use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Errno         qw/EAGAIN/;
use FileHandle;

=head1 NAME

Mail::Box::Locker::Flock - lock a folder using kernel file-locking

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::Flock> object lock the folder by creating an exclusive lock on
the file using the kernel's C<flock> facilities.  This lock is created
on a separate file-handle to the folder file, so not the handle which
is reading.

File locking does not work in some situations, for instance for
operating systems do not support C<flock>.

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

sub name() {'FLOCK'}

#-------------------------------------------

=head2 Locking

=cut

#-------------------------------------------

sub _try_lock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_EX|LOCK_NB;
}

sub _unlock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_UN;
    delete $self->{MBL_has_lock};
    $self;
}

#-------------------------------------------

# 'r+' is require under Solaris and AIX, other OSes are satisfied with 'r'.
my $lockfile_access_mode = ($^O eq 'solaris' || $^O eq 'aix') ? 'r+' : 'r';

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $filename = $self->filename;

    my $file   = FileHandle->new($filename, $lockfile_access_mode);
    unless($file)
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

        if($! != EAGAIN)
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

    my $file     = FileHandle->new($filename, $lockfile_access_mode);
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