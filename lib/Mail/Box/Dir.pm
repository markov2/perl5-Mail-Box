
use strict;
package Mail::Box::Dir;

use base 'Mail::Box';

use Mail::Box::Dir::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;
use Mail::Message::Head::Delayed;

use Carp;
use File::Copy;
use File::Spec;
use File::Basename;

=chapter NAME

Mail::Box::Dir - handle folders with a file per message.

=chapter SYNOPSIS

 # Do not instantiate this object

=chapter DESCRIPTION

This documentation describes the way directory organized mailboxes work.
At the moment, this object is extended by

=over 4

=item * M<Mail::Box::MH>
MH folders, which are represented by a directory containing files which
are sequentially numbered.

=item * M<Mail::Box::Maildir>
Maildir folders, which are located in a directory which has sub-directories
named C<tmp>, C<new>, and C<cur>.  Each of these directories may contain
files with names which are a combination of a numeric timestamp and some
status flags.

=item * Mail::Box::Netzwert
This folder type was especially developed for Netzwert AG, optimized to
run on a cluster of servers with folders on NFS.  The code is not publicly
available (yet).

=back

=chapter METHODS

=c_method new OPTIONS

=default body_type M<Mail::Message::Body::Lines>
=default lock_file <folder>C</.lock>

=warning Folder directory $directory is write-protected.

The folder directory does already exist and is write protected, which may
interfere with the requested write access.  Change new(access) or the
permissions on the directory.

=cut

sub init($)
{   my ($self, $args)    = @_;

    $args->{body_type} ||= sub {'Mail::Message::Body::Lines'};

    return undef
        unless $self->SUPER::init($args);

    my $class            = ref $self;
    my $directory        = $self->{MBD_directory}
       = $class->folderToDirectory($self->name, $self->folderdir);

       if(-d $directory) {;}
    elsif($args->{create} && $class->create($directory, %$args)) {;}
    else
    {   $self->log(PROGRESS => "$class: No directory $directory.\n");
        return undef;
    }

    # About locking

    for($args->{lock_file})
    {   $self->locker->filename
          ( !defined $_ ? File::Spec->catfile($directory, '.lock')   # default
          : File::Spec->file_name_is_absolute($_) ? $_               # absolute
          :               File::Spec->catfile($directory, $_)        # relative
          );
    }

    # Check if we can write to the folder, if we need to.

    if($self->writable && -e $directory && ! -w $directory)
    {   $self->log(WARNING => "Folder directory $directory is write-protected.\n");
        $self->{MB_access} = 'r';
    }

    $self;
}

#-------------------------------------------

sub organization() { 'DIRECTORY' }

#-------------------------------------------

=section The folder

=method directory

Returns the directory related to this folder.

=example
 print $folder->directory;

=cut

sub directory() { shift->{MBD_directory} }

#-------------------------------------------
                                                                                
sub nameOfSubFolder($)
{   my ($self, $name) = @_;
    $self->directory.'/'.$name;
}

#-------------------------------------------

=section Internals

=method folderToDirectory FOLDERNAME, FOLDERDIR

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToDirectory($$)
{   my ($class, $name, $folderdir) = @_;
    $name =~ /^=(.*)/ ? File::Spec->catfile($folderdir,$1) : $name;
}

#-------------------------------------------

=method readMessageFilenames DIRECTORY

Returns a list of all filenames which are found in this folder
directory and represent a message.  The filenames are returned as
relative path.

=cut

sub readMessageFilenames() {shift->notImplemented}

#-------------------------------------------

1;
