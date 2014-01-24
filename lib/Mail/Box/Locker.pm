
use strict;

package Mail::Box::Locker;
use base 'Mail::Reporter';

use Carp;
use Scalar::Util 'weaken';

#-------------------------------------------

=chapter NAME

Mail::Box::Locker - manage the locking of mail folders

=chapter SYNOPSIS

 use Mail::Box::Locker;
 my $locker = new Mail::Box::Locker(folder => $folder);

 $locker->lock;
 $locker->isLocked;
 $locker->hasLock;
 $locker->unlock;

 use Mail::Box;
 my $folder = Mail::Box->new(lock_method => 'DOTLOCK');
 print $folder->locker->type;

=chapter DESCRIPTION

Each M<Mail::Box> will create its own C<Mail::Box::Locker> object which
will handle the locking for it.  You can access of the object directly
from the folder, as shown in the examples below.

=chapter METHODS

=c_method new %options

Create a new lock. You may do this directly. However, in most cases the
lock will not be separately instantiated but will be the second class in
a multiple inheritance construction with a M<Mail::Box>.

Generally the client program specifies the locking behavior through
options given to the folder class.

=option  method STRING|CLASS|ARRAY
=default method C<'DOTLOCK'>

Which kind of locking, specified as one of the following names as STRING.
You may also specify a CLASS name, or an ARRAY of names.  In case of an
ARRAY, a 'multi' locker is started with all thee 
full CLASS name.

Supported locking names are

=over 4

=item 'DOTLOCK' | 'dotlock'

The folder handler creates a file which signals that it is in use.  This
is a bit problematic, because not all mail-handling software agree on
the name of the file to be created.

On various folder types, the lockfile differs.  See the documentation for
each folder, which describes the locking strategy as well as special
options to change the default behavior.

=item 'FLOCK' | 'flock'
For some folder handlers, locking is based on a file locking mechanism
provided by the operating system.  However, this does not work on all
systems, such as network filesystems, and such. This also doesn't work on
folders based on directories (M<Mail::Box::Dir> and derived).

=item 'FCNTLLOCK' | 'fcntllock'
POSIX locking via M<File::FcntlLock>, which works on more platforms.
However, that module requires a C compiler to install.

=item 'POSIX' | 'posix'
Use the POSIX standard fcntl locking.

=item 'MULTI' | 'multi'
Use ALL available locking methods at the same time, to have a bigger
chance that the folder will not be modified by some other application
which uses an unspecified locking method.  When one of the locking
methods disallows access, the locking fails.

=item 'MUTT'| 'mutt'
Use the external program 'mutt_dotlock' to lock and unlock.

=item 'NFS' | 'nfs'
A kind of C<dotlock> file-locking mechanism, but adapted to work over
NFS.  Extra precaution is needed because an C<open O_EXCL> on NFS is
not an atomic action.

=item 'NONE' | 'none'
Do not use locking.

=back

The other option is to produce your own C<Mail::Box::Locker> derived class,
which implements the desired locking method. (Please consider offering it
for inclusion in the public Mail::Box module!) Create an instance of that
class with this parameter:

 my $locker = Mail::Box::Locker::MyOwn->new;
 $folder->open(locker => $locker);

=option  expires SECONDS
=default expires 1 hour

How long can a lock exist?  If a different e-mail program leaves a stale
lock, then this lock will be removed automatically after the specified
number of seconds.

=option  folder FOLDER
=default folder <undef>
Which FOLDER is to be locked, a M<Mail::Box> object.

=option  timeout SECONDS|'NOTIMEOUT'
=default timeout 10 seconds

How long to wait while trying to acquire the lock. The lock request will
fail when the specified number of seconds is reached.  If C<'NOTIMEOUT'> is
specified, the module will wait until the lock can be taken.

Whether it is possible to limit the wait time is platform- and
locking-method-specific.  For instance, the `dotlock' method on Windows
will always wait until the lock has been received.

=option  file FILENAME
=default file undef

Name of the file to lock.  By default, the name of the folder is taken.

=cut

my %lockers =
  ( DOTLOCK   => __PACKAGE__ .'::DotLock'
  , FCNTLLOCK => __PACKAGE__ .'::FcntlLock'
  , FLOCK     => __PACKAGE__ .'::Flock'
  , MULTI     => __PACKAGE__ .'::Multi'
  , MUTT      => __PACKAGE__ .'::Mutt'
  , NFS       => __PACKAGE__ .'::NFS'
  , NONE      => __PACKAGE__
  , POSIX     => __PACKAGE__ .'::POSIX'
  );

sub new(@)
{   my $class  = shift;

    return $class->SUPER::new(@_)
        unless $class eq __PACKAGE__;

    # Try to figure out which locking method we really want (bootstrap)

    my %args   = @_;
    my $method = !defined $args{method}       ? 'DOTLOCK'
               : ref $args{method} eq 'ARRAY' ? 'MULTI'
               :                                 uc $args{method};

    my $create = $lockers{$method} || $args{$method};

    local $"   = ' or ';
    confess "No locking method $method defined: use @{[ keys %lockers ]}"
        unless $create;

    # compile the locking module (if needed)
    eval "require $create";
    confess $@ if $@;

    $args{use} = $args{method} if ref $args{method} eq 'ARRAY';

    $create->SUPER::new(%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MBL_expires}  = $args->{expires}   || 3600;  # one hour
    $self->{MBL_timeout}  = $args->{timeout}   || 10;    # ten secs
    $self->{MBL_filename} = $args->{file}      || $args->{folder}->name;
    $self->{MBL_has_lock} = 0;

    $self->folder($args->{folder});
    $self;
}

#-------------------------------------------

=section The Locker

=method name
Returns the method used to lock the folder. See the M<new(method)> for
details on how to specify the lock method.  The name of the method is
returned in upper-case.

=examples
 if($locker->name eq 'FLOCK') ...

=cut

sub name {shift->notImplemented}

sub lockMethod($$$$)
{   confess "Method removed: use inheritance to implement own method."
}

=method folder [$folder]
Returns the folder object which is locker.
=cut

sub folder(;$)
{   my $self = shift;
    @_ && $_[0] or return $self->{MBL_folder};

    $self->{MBL_folder} = shift;
    weaken $self->{MBL_folder};
}

=method filename [$filename]
Returns the filename which is used to lock the folder, optionally after
setting it to the specified $filename.

=example
 print $locker->filename;

=cut

sub filename(;$)
{   my $self = shift;
    $self->{MBL_filename} = shift if @_;
    $self->{MBL_filename};
}

#-------------------------------------------

=section Locking

=method lock $folder
Get a lock on a folder.  This will return false if the lock fails.

=examples
 die unless $locker->lock;
 if($folder->locker->lock) {...}
=cut

sub lock($) { shift->{MBL_has_lock} = 1 }

=method isLocked
Test if the folder is locked by this or a different application.

=examples
 if($locker->isLocked) {...}
 if($folder->locker->isLocked) {...}
=cut

sub isLocked($) {0}

=method hasLock
Check whether the folder has the lock.

=examples
 if($locker->hasLock) {...}
 if($folder->locker->hasLock) {...}

=cut

sub hasLock() {shift->{MBL_has_lock}}

=method unlock
Undo the lock on a folder.

=examples
 $locker->unlock;
 $folder->locker->unlock;

=cut

# implementation hazard: the unlock must be self-reliant, without
# help by the folder, because it may be called at global destruction
# after the folder has been removed.

sub unlock() { shift->{MBL_has_lock} = 0 }

#-------------------------------------------

=section Error handling

=section Cleanup

=method DESTROY

When the locker is destroyed, for instance when the folder is closed
or the program ends, the lock will be automatically removed.

=cut

sub DESTROY()
{   my $self = shift;
    $self->unlock if $self->hasLock;
    $self->SUPER::DESTROY;
    $self;
}

1;
