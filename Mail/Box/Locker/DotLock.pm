
use strict;

package Mail::Box::Locker::DotLock;
use base 'Mail::Box::Locker';

use IO::File;
use Carp;
use File::Spec;

=head1 NAME

Mail::Box::Locker::DotLock - lock a folder with a separate file

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::DotLock> object lock the folder by creating a file with the
same name as the folder, extended by C<.lock>.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=option  file FILENAME
=default file <folderfile>.lock

Name of the file to lock.  By default, the folder's name is extended with
C<.lock>.

=cut

sub init($)
{   my ($self, $args) = @_;

    unless($args->{file})
    {   my $folder = $args->{folder} or confess;
        my $org    = $folder->organization;

        $args->{file}
          = $org eq 'FILE'      ? $folder->filename . '.lock'
          : $org eq 'DIRECTORY' ? File::Spec->catfile($folder->directory, '.lock')
          : croak "Need lock file name for DotLock.";
    }

    $self->SUPER::init($args);
}

#-------------------------------------------

=method new OPTIONS

=cut

#-------------------------------------------

=head2 The Locker

=cut

#-------------------------------------------

sub name() {'DOTLOCK'}

#-------------------------------------------

=head2 Locking

=cut

#-------------------------------------------

sub _try_lock($)
{   my ($self, $lockfile) = @_;
    return if -e $lockfile;

    my $flags    = $^O eq 'MSWin32'
                 ?  O_CREAT|O_EXCL|O_WRONLY
                 :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock     = IO::File->new($lockfile, $flags, 0600)
        or return 0;

    close $lock;
    1;
}

#-------------------------------------------

sub unlock()
{   my $self = shift;
    return $self unless $self->{MBL_has_lock};

    my $lock = $self->filename;

    unlink $lock
        or warn "Couldn't remove lockfile $lock: $!\n";

    delete $self->{MBL_has_lock};
    $self;
}

#-------------------------------------------

sub lock()
{   my $self   = shift;
    return 1 if $self->hasLock;

    my $lockfile = $self->filename;
    my $end      = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1
                 : $self->{MBL_timeout};
    my $expire   = $self->{MBL_expires}/86400;  # in days for -A

    while(1)
    {
        return $self->{MBL_has_lock} = 1
           if $self->_try_lock($lockfile);

        if(-e $lockfile && -A $lockfile > $expire)
        {
            if(unlink $lockfile)
            {   warn "Removed expired lockfile $lockfile.\n";
                redo;
            }
            else
            {   warn "Failed to remove expired lockfile $lockfile: $!\n";
                last;
            }
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

#-------------------------------------------

sub isLocked() { -e shift->filename }

1;

