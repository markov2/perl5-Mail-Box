
use strict;

package Mail::Box::Locker;
use base 'Mail::Reporter';

use Carp;
our $VERSION = '2.00_07';

=head1 NAME

 Mail::Box::Locker - Manage the locking of mail folders

=head1 CLASS HIERARCHY

 Mail::Box::Locker
 is a Mail::Reporter

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

The locker module provides the locking functionality needed when handling
mail-folders.

Each C<Mail::Box> will create its own C<Mail::Box::Locker> object which will
handle the locking for it.  You can access of the object directly from
the folder, as shown in the examples below.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Locker> objects:

   MR errors                               name
      filename                             new OPTIONS
      hasLock                           MR report [LEVEL]
      isLocked                          MR reportAll [LEVEL]
      lock FOLDER                       MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]               unlock

The extra methods for extension writers:

   MR logPriority LEVEL                 MR logSettings

Prefixed methods are descibed in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new lock. You may do this directly. However, in most cases the
lock will not be separately instantiated but will be the second class in
a multiple inheritance construction with a L<Mail::Box>.

Generally the client program specifies the locking behavior through
options given to the folder class. ARGS is a reference to a hash, where
the following fields are used for the locker information:

=over 4

=item * lock_method =E<gt> METHOD | OBJECT

Which METHOD has to be used for locking.  Supported methods are

=over 4

=item 'DOTLOCK' | 'dotlock'

The folder handler creates a file which signals that it is in use.  This
is a bit problematic, because not all mail-handling software agree on
the name of the file to be created.

On various folder types, the lockfile differs.  See the documentation for
each folder, which describes the locking strategy as well as special
options to change the default behavior.

=item 'FILE' | 'file'

For some folder handlers, locking is based on a file locking mechanism
provided by the operating system.  However, this does not work on all
systems, such as network filesystems, and such. This also doesn't work on
folders based on directories (C<Mail::Box::MH> and derived).

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
   $folder->open(lock_method => $locker);

=item * lock_timeout =E<gt> SECONDS

How long can a lock exist?  If a different e-mail program leaves a stale
lock, then this lock will be removed automatically after the specified
number of seconds. The default is one hour.

=item * lock_wait =E<gt> SECONDS|'NOTIMEOUT'

How long to wait while trying to acquire the lock. The lock request will
fail when the specified number of seconds is reached.  If 'NOTIMEOUT' is
specified, the module will wait until the lock can be taken.

Whether it is possible to limit the wait time is platform- and
locking-method-specific.  For instance, the `dotlock' method on Windows
will always wait until the lock has been received.

=item * lock_file =E<gt> FILENAME

Name of the file to lock, or the name of the lockfile (depends on the
kind of lock used).

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

Returns the method used to lock the folder. See the C<new> method for
details on how to specify the lock method.  The name of the method is
returned in uppercase.  You can also get the name of the locking method
via the C<lockMethod> call of a C<Mail::Box> folder.

Examples:

    if($locker->name eq 'FILE') ...
    if($folder->lockMethod eq 'FILE') ...

=cut

sub name() { uc(shift->{MBL_method}) }

#-------------------------------------------

sub lockMethod($$$$)
{   confess "Method removed: use inheritance to implement own method."
}

#-------------------------------------------
#
# These default methods are the implementation of the 'NONE' method.
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

# implementation hazard: the unlock must be self-reliant, without
# help by the folder, because it may be called at global destruction
# after the folder has been removed.

sub unlock() { shift->{MBL_has_lock} = 0 }

#-------------------------------------------

=item filename

Returns the filename which is used to lock the folder.  How this file is
used depends on the locking method.

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

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_07.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
