
use strict;

package Mail::Box::Locker::File;
use base 'Mail::Box::Locker';

use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Errno         qw/EAGAIN/;

=head1 NAME

 Mail::Box::Locker::File - lock a folder using kernel file-locking

=head1 CLASS HIERARCHY

 Mail::Box::Locker::File
 is a Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::File> object lock the folder by creating an exclusive lock on
the file using the kernel's C<flock()> facilities.

File locking does not work for in situations, for instance some
operating systems do not support C<flock()>.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Locker::File> objects:

   MR errors                           MBL name
  MBL filename                         MBL new OPTIONS
  MBL hasLock                           MR report [LEVEL]
  MBL isLocked                          MR reportAll [LEVEL]
  MBL lock FOLDER                       MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]           MBL unlock

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBL = L<Mail::Box::Locker>

=head1 METHODS

=over 4

=cut

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

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_06.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;