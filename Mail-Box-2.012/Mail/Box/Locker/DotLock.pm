
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

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Box::Locker> (MBL).

The general methods for C<Mail::Box::Locker::DotLock> objects:

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

=head1 METHODS

=cut

#-------------------------------------------

sub name() {'DOTLOCK'}

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
{   my $self  = shift;
    return 1 if $self->hasLock;

    my $lockfile = $self->filename;
    my $end   = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1 : $self->{MBL_timeout};
    my $timer = 0;

    while($timer < $end)
    {   return $self->{MBL_has_lock} = 1
           if $self->_try_lock($lockfile);

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

#-------------------------------------------

sub isLocked() { -e shift->filename }

#-------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.012.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
