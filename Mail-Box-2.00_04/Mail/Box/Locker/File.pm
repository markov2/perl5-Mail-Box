
use strict;

package Mail::Box::Locker::File;
use Mail::Box::Locker;
use vars '@ISA';
@ISA = 'Mail::Box::Locker';

use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Errno         qw/EAGAIN/;

# For documentation, see Mail::Box::Locker

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

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $file  = $self->{MBL_folder}->filehandle;
    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? 0 : $self->{MBL_timeout};
    my $timer = 0;

    while($timer != $end)
    {   if($self->_try_lock($file))
        {   $self->{MBL_has_lock} = 1;
            return 1;
        }

        if($! != EAGAIN)
        {   warn "Will never get a lock at ".$self->{MBL_folder}->name.": $!\n";
            return 0;
        }

        sleep 1;
        $timer++;
    }

    return 0;
}

sub isLocked()
{   my $self  = shift;
    my $file  = $self->{MBL_folder}->filehandle;

    $self->_try_lock($file) or return 0;
    $self->_unlock($file);
    1;
}

sub unlock()
{   my $self   = shift;
    return $self unless $self->hasLock;

    my $folder = $self->{MBL_folder};
    warn "File-handle already closed: lock already broken."
       unless $folder->fileIsOpen;

    $self->_unlock($folder->filehandle);
}

1;
