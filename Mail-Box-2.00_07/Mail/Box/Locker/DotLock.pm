
use strict;

package Mail::Box::Locker::DotLock;
use base 'Mail::Box::Locker';

use IO::File;
use Carp;

=head1 NAME

 Mail::Box::Locker::DotLock - lock a folder with a seperate file

=head1 CLASS HIERARCHY

 Mail::Box::Locker::DotLock
 is a Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

The C<::DotLock> object lock the folder by creating a file with the
same name as the folder, extended by C<.lock>.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Locker::DotLock> objects:

   MR errors                           MBL name
  MBL filename                         MBL new OPTIONS
  MBL hasLock                           MR report [LEVEL]
  MBL isLocked                          MR reportAll [LEVEL]
  MBL lock FOLDER                       MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]           MBL unlock

The extra methods for extension writers:

   MR logPriority LEVEL                 MR logSettings

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBL = L<Mail::Box::Locker>

=head1 METHODS

=over 4

=cut

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
