
use strict;

package Mail::Box::Locker;
use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Sys::Hostname;

=head1 NAME

Mail::Box::Locker - Manage the locking of mail-folders

=head1 SYNOPSIS

   use Mail::Box::Locker;
   my $locker = new Mail::Box::Locker;

   $locker->lock($folder);
   $locker->isLocked($folder);
   $locker->hasLock($folder);
   $locker->unlock($folder);

   Mail::Box::Locker->addLockingMethod(...);

   # Because Mail::Box inherits from this class:
   my $folder = new Mail::Box(lock_method => 'dotlock');
   $folder->lock;
   $folder->isLocked;
   $folder->hasLock;
   $folder->unlock;

=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.
The locker module contains the various locking functionalities as
needed when handling folders.

Because C<Mail::Box> inherits from Mail::Box::Locker, this
example works:

    my $folder
    $folder->lock;

=head1 METHOD

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new lock.  You may do this, however, in most cases the lock will
not be seperately instantiated but be the second class in a multiple
inheritance construction with a L<Mail::Box>.

ARGS is a reference to a hash, where the following fields are used
for the locker information:

=over 4

=item * lock_method =E<gt> METHOD

Which METHOD has to be used for locking.  Supported are

=over 4

=item 'dotlock'

The folder handler creates a file which signals that it is in use.  This
is a bit problematic, because all mail-handling software should agree on
the name of the file to be created.

On various folder-types, the lockfile differs.  See each manual-page
and special options to change their default behavior.

=item 'file'

For some folder handlers, locking is based on simply file-locking
mechanism.  However, this does not work on network filesystems, and
such.  This also doesn't work on directory-type of folders (Mail::Box::Dir
and derived).

=item 'nfs'

A kind of C<dotlock> file-locking mechanism, but adapted to work over
NFS.  Extra precaution is needed because an C<open O_EXCL> on NFS is
not an atomic action.

=item 'NONE'

Disable locking.

=back

=item * lock_timeout =E<gt> SECONDS

How long can a lock stand?  When an different e-mail program left a
lock, then this will be removed automatically after the specified
seconds.  The default is one hour.

=item * lock_wait =E<gt> SECONDS|'NOTIMEOUT'

How long to wait for receiving the lock.  The lock-request may fail,
when the specified number of seconds is reached.  If 'NOTIMEOUT' is
specified, we wait till the lock can be taken.

It is platform and locking method specific whether it is possible at
all to limit the trials to the specified number of seconds.  For instance,
the `dotlock' method on Windows will always wait until the lock has been
received.

=item * lockfile =E<gt> FILENAME

Name of the file to take the lock on or to represent a lock (depends on
the kind of lock used).

=back

=cut

my %lock_methods
= ( dotlock => [ qw/dot_lock   dot_test_lock  dot_unlock/  ]
  , file    => [ qw/file_lock  file_test_lock file_unlock/ ]
  , nfs     => [ qw/nfs_lock   nfs_test_lock  nfs_unlock/  ]
  , NONE    => [ sub {1}, sub {0}, sub {} ]
  );

sub new(@) { (bless {}, shift)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;

    my $method = $args->{lock_method} || 'dotlock';
    unless(exists $lock_methods{$method})
    {   warn "Unknown lock method $method: locking disabled.\n";
        $method = 'NONE';
    }

    $self->{MBL_method}   = $method;
    $self->{MBL_timeout}  = 3600;
    $self->{MBL_wait}     = 10;
    $self->{MBL_haslock}  = 0;
    $self->lockFilename($args->{lockfile}) if $args->{lockfile};

    $self;
}

#-------------------------------------------

=item lockingMethod NAME, CODE, CODE, CODE

(class method)  Add locking methods to the set of know methods.  You
need to specify a method-name and three code references, respectively
for the get, test, and un method.  You may also specify method-names
instead of code-references.

=cut

sub lockingMethod($$$$)
{   my ($class, $name) = (shift, shift);
    $lock_methods{$name} = [ @_ ];
    $class;
}

#-------------------------------------------

=back

=head2 Basic functions

The C<lock>, C<test_lock>, and C<unlock> methods are to be
used.  They call specific methods which implement the right locking
mechanism.   I<Do not call> the various locking methods directly.

=over 4

=item lock [FOLDER] [METHOD]

Get a lock on a folder, by using the predefined method, or a
specific METHOD.  If you do not specify a FOLDER, it is
assumed the locking functionality is inherited.

Examples:

    $locker->lock($folder);
    $folder->lock;

=cut

sub lock(;$$)
{   my $self     = shift;
    my $folder   = ref $_[0] ? shift : $self;
    my $method   = @_ ? shift : $self->{MBL_method};

    # Never lock twice.
    return 1 if $folder->hasLock;

    my $function = $lock_methods{$method}[0];
    unless(defined $function)
    {   warn "Unknown locking method $method.\n";
        return 1;
    }

    no strict 'refs';
    ref $function ? $function->($folder) : $self->$function($folder);
}

#-------------------------------------------

=item isLocked [FOLDER] [METHOD]

Test if the folder is locked.

Examples:

    $locker->isLocked($folder);
    $folder->isLocked;

=cut

sub isLocked(;$$)
{   my $self     = shift;
    my $folder   = ref $_[0] ? shift : $self;
    my $method   = @_ ? shift : $self->{MBL_method};

    my $function = $lock_methods{$method}[1];
    unless(defined $function)
    {   warn "Unknown locking method $method.\n";
        return 0;
    }

    no strict 'refs';
    ref $function ? $function->($folder) : $self->$function($folder);
}

#-------------------------------------------

=item hasLock [FOLDER]

Check wheter the folder has the lock.

Examples:

    $locker->hasLock($folder);
    $folder->hasLock;

=cut

sub hasLock(;$)
{   my $self   = shift;
    my $folder = ref $_[0] ? shift : $self;
    $self->{MBL_haslock};
}

#-------------------------------------------

=item unlock [FOLDER] [METHOD]

un the lock on a folder.

Examples:

    $locker->unlock($folder);
    $folder->unlock;

=cut

sub unlock(;$$)
{   my $self     = shift;
    my $folder   = ref $_[0] ? shift : $self;
    my $method   = @_ ? shift : $self->{MBL_method};

    my $function = $lock_methods{$method}[2];
    unless(defined $function)
    {   warn "Unknown locking method $method.\n";
        return 1;
    }

    no strict 'refs';
    ref $function ? $function->($folder) : $self->$function($folder);
    delete $self->{MBL_haslock};
}

#-------------------------------------------

=item lockFilename [FILENAME]

Returns the filename which is used to lock the folder.  It depends on the
locking method how this file is used.

=cut

sub lockFilename(;$)
{   my $self = shift;
    @_ ? $self->{MBL_lockfile} = shift : $self->{MBL_lockfile};
}

#-------------------------------------------
# METHOD dotlock

sub try_dot_lock($)
{   my ($self, $lockfile) = @_;

    my $flags = $^O eq 'MSWin32'
              ?  O_CREAT|O_EXCL|O_WRONLY
              :  O_CREAT|O_EXCL|O_WRONLY|O_NONBLOCK;

    my $lock  = IO::File->new($lockfile, $flags, 0600) or return 0;

    $self->{MBL_haslock} = $lockfile;
    close $lock;

    1;
}

sub do_dot_unlock($)
{   my $self = shift;
    my $lock = $self->{MBL_haslock};
    unlink $lock or warn "Couldn't remove lockfile $lock: $!\n";
    delete $self->{MBL_haslock};
    $self;
}

sub dot_lock
{   my ($self, $folder) = @_;
    my $lockfile = $folder->lockFilename;
    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};
    my $timer = 0;

    while($timer != $end)
    {   return 1 if $self->try_dot_lock($lockfile);

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

sub dot_test_lock($)
{   my ($self, $folder) = @_;
    my $lockfile = $folder->lockFilename;

    $self->try_dot_lock($lockfile) or return 0;
    $self->do_dot_unlock;

    1;
}

sub dot_unlock($)
{   my ($self, $folder) = @_;
    return unless $self->hasLock;
    $self->do_dot_unlock;
}


#-------------------------------------------
# METHOD file

sub try_file_lock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_EX|LOCK_NB;
}

sub do_file_unlock($)
{   my ($self, $file) = @_;
    flock $file, LOCK_UN;
}

sub file_lock
{   my ($self, $folder) = @_;
    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? 0 : $self->{MBL_timeout};
    my $file  = $folder->filehandle;

    my $timer = 0;
    while($timer != $end)
    {   if($self->try_file_lock($file))
        {   $self->{MBL_haslock} = $folder;
            return 1;
        }

        sleep 1;
        $timer++;
    }

    return 0;
}

sub file_test_lock($)
{   my ($self, $folder) = @_;
    my $file  = $folder->filehandle;

    $self->try_file_lock($file) or return 0;
    $self->do_file_unlock($file);
    1;
}

sub file_unlock($)
{   my ($self, $folder) = @_;
    return unless $self->hasLock;
    $self->do_dot_unlock($folder->filehandle);
}

#-------------------------------------------
# METHOD nfs
# This hack is copied from the Mail::Folder packages, as written
# by Kevin Jones.  Cited from his code:
#    Whhheeeee!!!!!
#    In NFS, the O_CREAT|O_EXCL isn't guaranteed to be atomic.
#    So we create a temp file that is probably unique in space
#    and time ($folder.lock.$time.$pid.$host).
#    Then we use link to create the real lock file. Since link
#    is atomic across nfs, this works.
#    It loses if it's on a filesystem that doesn't do long filenames.

my $hostname = hostname;

sub tmpfilename($)
{   my ($self, $folder) = @_;
    $folder->name . ".lock." . time . ".$$.$hostname";
}

sub construct_tmpfile($)
{   my ($self, $folder) = @_;

    my $tmpfile = $self->tmpfilename($folder);
    my $fh = IO::File->new($tmpfile, O_CREAT|O_WRONLY, 0600) or return;

    $fh->close;
    $tmpfile;
}

sub try_nfs_lock($)
{   my ($self, $tmpfile, $lockfile) = @_;
    link $tmpfile, $lockfile
        or warn "Cannot link $lockfile to $tmpfile.\n";
    my $success = ((stat $tmpfile)[2] == 2);
    unlink $tmpfile;
    $success;
}

sub do_nfs_unlock($)
{   my ($self, $lockfile) = @_;
    unlink $lockfile or warn "Couldn't remove lockfile $lockfile: $!\n";
    $self;
}

sub NFS_lock
{   my ($self, $folder) = @_;

    # Create a file to link to
    my $tmpfile  = $self->construct_tmpfile($folder) or return;
    my $lockfile = $folder->filename.'.lock';
    my $end  = $self->{MBL_timeout} eq 'NOTIMEOUT' ? 0 : $self->{MBL_timeout};

    my $timer = 0;
    while($timer != $end)
    {   if(my $fh = $self->try_nfs_lock($tmpfile, $lockfile))
        {   $fh->close;
            $self->{MBL_haslock} = $lockfile;
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

sub NFS_test_lock($)
{   my ($self, $folder) = @_;
    my $tmpfile  = $self->construct_tmpfile($folder) or return 0;
    my $lockfile = $folder->filename.'.lock';

    my $fh = $self->try_dot_lock($tmpfile, $lockfile) or return 0;

    close $fh;
    $self->do_nfs_unlock($tmpfile, $lockfile);
    1;
}

sub NFS_unlock($)
{   my ($self, $folder) = @_;
    return unless $self->hasLock;

    $self->do_nfs_unlock
     ( $self->tmpfilename($folder)
     , $folder->filename.'.lock'
     );
}

#-------------------------------------------

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.000

=cut

1;
