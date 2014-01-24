
use strict;

package Mail::Box::Locker::DotLock;
use base 'Mail::Box::Locker';

use IO::File;
use File::Spec;
use Errno      qw/EEXIST/;
use Carp;

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

=option  dotlock_file FILENAME
=default dotlock_file <undef>
Alternative name for C<file>, especially useful to confusion when
the multi locker is used.
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{file} = $args->{dotlock_file} if $args->{dotlock_file};
    $self->SUPER::init($args);
}

sub name() {'DOTLOCK'}

sub folder(;$)
{   my $self = shift;
    @_ && $_[0] or return $self->SUPER::folder;

    my $folder = shift;
    unless(defined $self->filename)
    {   my $org = $folder->organization;

        my $filename
          = $org eq 'FILE'     ? $folder->filename . '.lock'
          : $org eq 'DIRECTORY'? File::Spec->catfile($folder->directory,'.lock')
          : croak "Need lock file name for DotLock.";

        $self->filename($filename);
    }

    $self->SUPER::folder($folder);
}

sub _try_lock($)
{   my ($self, $lockfile) = @_;
    return if -e $lockfile;

    my $flags    = $^O eq 'MSWin32'
                 ?  O_CREAT|O_EXCL|O_WRONLY
                 :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock = IO::File->new($lockfile, $flags, 0600);
    if($lock)
    {   close $lock;
        return 1;
    }

    if($! != EEXIST)
    {   $self->log(ERROR => "lockfile $lockfile can never be created: $!");
        return 1;
    }
}

=method unlock
=warning Couldn't remove lockfile $lock: $!
=cut

sub unlock()
{   my $self = shift;
    $self->{MBL_has_lock}
        or return $self;

    my $lock = $self->filename;

    unlink $lock
        or $self->log(WARNING => "Couldn't remove lockfile $lock: $!");

    delete $self->{MBL_has_lock};
    $self;
}

=method lock
=warning Folder already locked with file $lockfile
=warning Removed expired lockfile $lockfile
=error Failed to remove expired lockfile $lockfile: $!
=cut

sub lock()
{   my $self   = shift;

    my $lockfile = $self->filename;
    if($self->hasLock)
    {   $self->log(WARNING => "Folder already locked with file $lockfile");
        return 1;
    }

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
            {   $self->log(WARNING => "Removed expired lockfile $lockfile");
                redo;
            }
            else
            {   $self->log(ERROR =>
                   "Failed to remove expired lockfile $lockfile: $!");
                last;
            }
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

sub isLocked() { -e shift->filename }

1;

