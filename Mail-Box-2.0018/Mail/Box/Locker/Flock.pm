
use strict;

package Mail::Box::Locker::Flock;
use base 'Mail::Box::Locker';

use Fcntl         qw/:DEFAULT :flock/;
use IO::File;
use Errno         qw/EAGAIN/;
use FileHandle;

=head1 NAME

Mail::Box::Locker::Flock - lock a folder using kernel file-locking

=head1 CLASS HIERARCHY

 Mail::Box::Locker::Flock
 is a Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::Flock> object lock the folder by creating an exclusive lock on
the file using the kernel's C<flock()> facilities.  This lock is created
on a separate file-handle to the folder file, so not the handle which
is reading.

File locking does not work in some situations, for instance for
operating systems do not support C<flock()>.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Locker::Flock> objects:

  MBL DESTROY                          MBL name
   MR errors                           MBL new OPTIONS
  MBL filename                          MR report [LEVEL]
  MBL hasLock                           MR reportAll [LEVEL]
  MBL isLocked                          MR trace [LEVEL]
  MBL lock FOLDER                      MBL unlock
   MR log [LEVEL [,STRINGS]]            MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBL = L<Mail::Box::Locker>

=head1 METHODS

=cut

#-------------------------------------------

sub name() {'FLOCK'}

#-------------------------------------------

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

#-------------------------------------------

sub lock()
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $filename = $self->filename;

    # 'r+' is require under Solaris, other OSes are satified with 'r'.
    my $access = $^O eq 'solaris' ? 'r+' : 'r';

    my $file   = FileHandle->new($filename, $access);
    unless($file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    my $end    = $self->{MBL_timeout} eq 'NOTIMEOUT' ? 0 : $self->{MBL_timeout};
    my $timer  = 0;

    while($timer != $end)
    {   if($self->_try_lock($file))
        {   $self->{MBL_has_lock}    = 1;
            $self->{MBLF_filehandle} = $file;
            return 1;
        }

        if($! != EAGAIN)
        {   $self->log(ERROR =>
                  "Will never get a lock at ".$self->{MBL_folder}->name.": $!");
            return 0;
        }

        sleep 1;
        $timer++;
    }

    return 0;
}

#-------------------------------------------

sub isLocked()
{   my $self     = shift;
    my $filename = $self->filename;

    # 'r+' is require under Solaris, other OSes are satified with 'r'.
    my $access   = $^O eq 'solaris' ? 'r+' : 'r';

    my $file     = FileHandle->new($filename, "r+");
    unless($file)
    {   $self->log(ERROR => "Unable to open lockfile $filename");
        return 0;
    }

    $self->_try_lock($file) or return 0;
    $self->_unlock($file);
    $file->close;

    1;
}

#-------------------------------------------

sub unlock()
{   my $self = shift;

    $self->_unlock(delete $self->{MBLF_filehandle})
       if $self->hasLock;

    $self;
}

#-------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
