
use strict;

package Mail::Box::Locker::DotLock;
use Mail::Box::Locker;
our @ISA = 'Mail::Box::Locker';

use IO::File;
use Carp;

# For documentation, see Mail::Box::Locker.

sub _try_lock($)
{   my ($self, $lockfile) = @_;

    my $flags    = $^O eq 'MSWin32'
                 ?  O_CREAT|O_EXCL|O_WRONLY
                 :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock     = IO::File->new($lockfile, $flags, 0600)
        or return 0;

    close $lock;
    1;
}

sub unlock()
{   my $self = shift;
    return $self unless $self->{MBL_has_lock};

    my $lock = $self->filename;

    unlink $lock
        or warn "Couldn't remove lockfile $lock: $!\n";

    delete $self->{MBL_has_lock};
    $self;
}

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $lockfile = $self->filename;
    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};
    my $timer = 0;

    while($timer != $end)
    {   if($self->_try_lock($lockfile))
        {   return $self->{MBL_has_lock} = 1;
            return 1;
        }

        if(   -e $lockfile
           && -A $lockfile > ($self->{MBL_timeout}/86400)
           && unlink $lockfile
          )
        {   warn "Removed expired lockfile $lockfile.\n";
            redo;
        }

        sleep 1;
        $timer++;
    }

    return 0;
}

sub isLocked()
{   my $self     = shift;
    $self->_try_lock($self->filename) or return 0;
    $self->unlock;
    1;
}

1;
