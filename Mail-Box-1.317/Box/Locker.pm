
use strict;

package Mail::Box::Locker;

use Carp;

=head1 NAME

Mail::Box::Locker - Manage the locking of mail-folders

=head1 SYNOPSIS

   use Mail::Box;
   use Mail::Box::Locker;
   my $locker = new Mail::Box::Locker(folder => $folder);

   $locker->lock;
   $locker->isLocked;
   $locker->hasLock;
   $locker->unlock;

   my $folder = new Mail::Box(lock_method => 'DOTLOCK');
   print $folder->lockMethod;
   $folder->lock;
   $folder->isLocked;
   $folder->hasLock;
   $folder->unlock;

=head1 DESCRIPTION

Read L<Mail::Box::Manager> first.
The locker module contains the various locking functionalities as
needed when handling mail-folders.

Each Mail::Box-folder will create its own Mail::Box::Locker object,
which will handle the locking for it.  You can access of the object
directly from the folder, as shown in the examples below.  Sometimes
the names of the methods had to be changed to avoid confusion.

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

=item * lock_method =E<gt> METHOD | OBJECT

Which METHOD has to be used for locking.  Supported are

=over 4

=item 'DOTLOCK' | 'dotlock'

The folder handler creates a file which signals that it is in use.  This
is a bit problematic, because all mail-handling software should agree on
the name of the file to be created.

On various folder-types, the lockfile differs.  See each manual-page
and special options to change their default behavior.

=item 'FILE' | 'file'

For some folder handlers, locking is based on simply file-locking
mechanism.  However, this does not work on network filesystems, and
such.  This also doesn't work on directory-type of folders (Mail::Box::Dir
and derived).

=item 'NFS' | 'nfs'

A kind of C<dotlock> file-locking mechanism, but adapted to work over
NFS.  Extra precaution is needed because an C<open O_EXCL> on NFS is
not an atomic action.

=item 'NONE' | 'none'

Disable locking.

=back

The other option (but this is implemented in Mail::Box) is to
produce your own Mail::Box::Locker derived class, which implements
the desired locking method [you may consider to offer it for inclusion
in the public Mail::Box module]   Create an instance of that class
with this parameter:

   my $locker = Mail::Box::Locker::MyOwn->new;
   $folder->open(lock_method => $locker);

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

=item * lock_file =E<gt> FILENAME

Name of the file to take the lock on or to represent a lock (depends on
the kind of lock used).

=back

=cut

my %lockers = ( DOTLOCK => __PACKAGE__ .'::DotLock'
              , FILE    => __PACKAGE__ .'::File'
              , NFS     => __PACKAGE__ .'::NFS'
              , NONE    => __PACKAGE__
              );

sub new(@)
{   my ($class, %args) = @_;
    my $method = uc $args{lock_method} || 'DOTLOCK';
    my $create = $lockers{$method};

    local $" = ' or ';
    confess "No locking method $method defined: use @{[ keys %lockers ]}"
        unless $create;

    $args{lock_method} = $method;

    # compile the locking module (if needed)
    eval "require $create";
    confess $@ if $@;

    (bless {}, $create)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->{MBL_folder}   = $args->{folder}
        or confess "No folder specified at creation lock-object.";

    $self->{MBL_method}   = $args->{lock_method};
    $self->{MBL_timeout}  = $args->{lock_timeout}   || 3600;
    $self->{MBL_wait}     = $args->{lock_wait}      || 10;
    $self->{MBL_lock_file}= $args->{lock_file};
    $self->{MBL_has_lock} = 0;

    $self;
}

#-------------------------------------------

=item name

Return the way this folder was locked.  It can only be set as option
to the creation of a folder.  The method-name is returned in uppercase.
You can also get the name of the locking method via the C<lockMethod>
call of a Mail::Box folder.

Examples:

    if($locker->name eq 'FILE') ...
    if($folder->lockMethod eq 'FILE') ...

=cut

sub name() { shift->{MBL_method} }

#-------------------------------------------

sub lockingMethod($$$$)
{   confess "Method removed: use inheritance to implement own method."
}

#-------------------------------------------
#
# These default methods are the implementation of the 'NONE'-method.
#

=back

=head2 Basic functions

=over 4

=item lock FOLDER

Get a lock on a folder.  This will return false if the lock fails.

Examples:

    die unless $locker->lock;
    if($folder->lock) {...}

=cut

sub lock($) { shift->{MBL_has_lock} = 1 }

#-------------------------------------------

=item isLocked

Test if the folder is locked by this or a different application.

Examples:

    if($locker->isLocked) {...}
    if($folder->isLocked) {...}

=cut

sub isLocked($) {0}

#-------------------------------------------

=item hasLock

Check whether the folder has the lock.

Examples:

    if($locker->hasLock) {...}
    if($folder->hasLock) {...}

=cut

sub hasLock() { shift->{MBL_has_lock} }

#-------------------------------------------

=item unlock

Undo the lock on a folder.

Examples:

    $locker->unlock;
    $folder->unlock;

=cut

# implementation hazard: the unlock must be self-suppliant, without
# help by the folder, because it may be called at global destruction
# after the folder has been removed.

sub unlock() { shift->{MBL_has_lock} = 0 }

#-------------------------------------------

=item filename

Returns the filename which is used to lock the folder.  It depends on the
locking method how this file is used.

Examples:

   print $locker->filename;
   print $folder->lockFilename;

=cut

sub filename($)
{   my $self   = shift;
    return $self->{MBL_filename} if defined $self->{MBL_filename};

    my $folder = $self->{MBL_folder};
    $self->{MBL_filename}
        = $folder->can('filename')  ? $folder->filename  . '.lock'
        : $folder->can('directory') ? $folder->directory . '/.lock'
        : croak "Need lock-file name.";
}

sub DESTROY()
{   my $self = shift;
    $self->unlock if $self->hasLock;
}

#-------------------------------------------

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.317

=cut

1;
