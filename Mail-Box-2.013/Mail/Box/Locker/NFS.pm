
use strict;

package Mail::Box::Locker::NFS;
use base 'Mail::Box::Locker';

use IO::File;
use Sys::Hostname;
use Carp;

=head1 NAME

Mail::Box::Locker::NFS - lock a folder with a seperate file, NFS-safe

=head1 CLASS HIERARCHY

 Mail::Box::Locker::NFS
 is a Mail::Box::Locker
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Box::Locker

=head1 DESCRIPTION

Like the C<::DotLock> locker, but then in an NFS-safe fashion.  Over NFS,
the creation of a file is not atomic.  The C<::DotLock> locker depends
on an atomic C<open()> hence in not usable.  The C<::NFS> locker is more
complicated (so slower), but will work for NFS -and for local disks too.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Box::Locker> (MBL).

The general methods for C<Mail::Box::Locker::NFS> objects:

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

sub name() {'NFS'}

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

sub _tmpfilename()
{   my $self = shift;
    return $self->{MBL_tmp} if $self->{MBL_tmp};

    my $folder = $self->{MBL_folder};
    $self->{MBL_tmp} = $self->filename . $$;
}

sub _construct_tmpfile()
{   my $self    = shift;
    my $tmpfile = $self->_tmpfilename;

    my $fh      = IO::File->new($tmpfile, O_CREAT|O_WRONLY, 0600)
        or return undef;

    $fh->close;
    $tmpfile;
}

sub _try_lock($$)
{   my ($self, $tmpfile, $lockfile) = @_;

    return undef
        unless link $tmpfile, $lockfile;

    my $linkcount = (stat $tmpfile)[3];

    unlink $tmpfile;
    $linkcount==2;
}

sub _unlock($$)
{   my ($self, $tmpfile, $lockfile) = @_;

    unlink $lockfile
        or warn "Couldn't remove lockfile $lockfile: $!\n";

    unlink $tmpfile;

    $self;
}

sub lock()
{   my $self     = shift;
    return 1 if $self->hasLock;

    my $folder   = $self->{MBL_folder};
    my $lockfile = $self->filename;
    my $tmpfile  = $self->_construct_tmpfile or return;
    my $end      = $self->{MBL_timeout} eq 'NOTIMEOUT' ? -1
                 : $self->{MBL_timeout};
    my $expires  = $self->{MBL_expires}/86400;  # in days for -A

    while(1)
    {   if($self->_try_lock($tmpfile, $lockfile))
        {   $self->{MBL_has_lock} = 1;
            return 1;
        }

        if(-e $lockfile && -A $lockfile > $expires)
        {   if(unlink $lockfile)
            {   warn "Removed expired lockfile $lockfile.\n";
                redo;
            }
            else
            {   warn "Unable to remove expired lockfile $lockfile: $!\n";
                last;
            }
        }

        last unless --$end;
        sleep 1;
    }

    return 0;
}

sub isLocked()
{   my $self     = shift;
    my $tmpfile  = $self->_construct_tmpfile or return 0;
    my $lockfile = $self->filename;

    my $fh = $self->_try_lock($tmpfile, $lockfile) or return 0;

    close $fh;
    $self->_unlock($tmpfile, $lockfile);
    1;
}

sub unlock($)
{   my $self   = shift;
    return $self unless $self->hasLock;

    $self->_unlock($self->_tmpfilename, $self->filename);
    delete $self->{MBL_has_lock};
    $self;
}

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.013.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
