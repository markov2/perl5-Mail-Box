
use strict;

package Mail::Box::Locker;
use base 'Mail::Reporter';

our $VERSION = 2.00_16;

use Carp;
use File::Spec;

#-------------------------------------------

=head1 NAME

Mail::Box::Locker - Manage the locking of mail folders

=head1 CLASS HIERARCHY

 Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Locker;
 my $locker = new Mail::Box::Locker(folder => $folder);

 $locker->lock;
 $locker->isLocked;
 $locker->hasLock;
 $locker->unlock;

 use Mail::Box;
 my $folder = Mail::Box->new(lock_method => 'DOTLOCK');
 print $folder->locker->type;

=head1 DESCRIPTION

Read L<Mail::Box-Overview> first.
The locker module provides the locking functionality needed when handling
mail-folders.

Each C<Mail::Box> will create its own C<Mail::Box::Locker> object which will
handle the locking for it.  You can access of the object directly from
the folder, as shown in the examples below.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Locker> objects:

      DESTROY                              name
   MR errors                               new OPTIONS
      filename                          MR report [LEVEL]
      hasLock                           MR reportAll [LEVEL]
      isLocked                          MR trace [LEVEL]
      lock FOLDER                          unlock
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new lock. You may do this directly. However, in most cases the
lock will not be separately instantiated but will be the second class in
a multiple inheritance construction with a L<Mail::Box>.

Generally the client program specifies the locking behavior through
options given to the folder class.

 OPTIONS        DESCRIBED IN               DEFAULT
 file           Mail::Box::Locker          undef
 log            Mail::Reporter             'WARNINGS'
 method         Mail::Box::Locker          'DOTLOCK'
 timeout        Mail::Box::Locker          1 hour
 trace          Mail::Reporter             'WARNINGS'
 wait           Mail::Box::Locker          10 seconds

=over 4

=item * method =E<gt> METHOD | CLASS

Which kind of locking, specified as one of the following names, or a
full CLASS name.  Supported METHODs are

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
folders based on directories (C<Mail::Box::MH> and derived).

=item 'MULTI' | 'multi'

Try more than one locking method to be used at the same time, probably
all available, to avoid any chance that you miss a lock from a different
application.

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

=item * timeout =E<gt> SECONDS

How long can a lock exist?  If a different e-mail program leaves a stale
lock, then this lock will be removed automatically after the specified
number of seconds.

=item * wait =E<gt> SECONDS|'NOTIMEOUT'

How long to wait while trying to acquire the lock. The lock request will
fail when the specified number of seconds is reached.  If 'NOTIMEOUT' is
specified, the module will wait until the lock can be taken.

Whether it is possible to limit the wait time is platform- and
locking-method-specific.  For instance, the `dotlock' method on Windows
will always wait until the lock has been received.

=item * file =E<gt> FILENAME

Name of the file to lock, or the name of the lockfile (depends on the
kind of lock used).

=back

=cut

my %lockers =
  ( DOTLOCK => __PACKAGE__ .'::DotLock'
  , FLOCK   => __PACKAGE__ .'::Flock'
  , MULTI   => __PACKAGE__ .'::Multi'
  , NFS     => __PACKAGE__ .'::NFS'
  , NONE    => __PACKAGE__
  );

sub new(@)
{   my $class  = shift;

    return $class->SUPER::new(@_)
        unless $class eq __PACKAGE__;

    my %args   = @_;
    my $method = defined $args{method} ? uc $args{method} : 'DOTLOCK';
    my $create = $lockers{$method} || $args{$method};

    local $" = ' or ';
    confess "No locking method $method defined: use @{[ keys %lockers ]}"
        unless $create;

    # compile the locking module (if needed)
    eval "require $create";
    confess $@ if $@;

    $create->SUPER::new(%args);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MBL_folder}   = $args->{folder};
    $self->{MBL_timeout}  = $args->{timeout}   || 3600;
    $self->{MBL_wait}     = $args->{wait}      || 10;
    $self->{MBL_filename} = $args->{file};
    $self->{MBL_has_lock} = 0;

    $self;
}

#-------------------------------------------

=item name

Returns the method used to lock the folder. See the C<new> method for
details on how to specify the lock method.  The name of the method is
returned in uppercase.  You can also get the name of the locking method
via the C<lockMethod> call of a C<Mail::Box> folder.

Example:

    if($locker->name eq 'FLOCK') ...

=cut

sub name {shift->notImplemented}

#-------------------------------------------

sub lockMethod($$$$)
{   confess "Method removed: use inheritance to implement own method."
}

#-------------------------------------------
#
# These default methods are the implementation of the 'NONE' method.
#

=back

=head1 METHODS

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
    if($folder->locker->hasLock) {...}

=cut

sub hasLock() {shift->{MBL_has_lock} }

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
    my $org    = $folder->organization;
    $self->{MBL_filename}
        = $org eq 'FILE'      ? $folder->filename . '.lock'
        : $org eq 'DIRECTORY' ? File::Spec->catfile($folder->directory, '.lock')
        : croak "Need lock-file name.";
}

#-------------------------------------------

=item DESTROY

When the locker is destroyed, for instance when the folder is closed
or the program ends, the lock will be automatically removed.

=cut

sub DESTROY()
{   my $self = shift;
    $self->unlock if $self->hasLock;
    $self->SUPER::DESTROY;
    $self;
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

This code is beta, version 2.00_16.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
