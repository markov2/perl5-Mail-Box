
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

=head1 NAME

Mail::Box::Dir - handle folders with a file per message.

=head1 SYNOPSIS

 # Do not instantiate this object

=head1 DESCRIPTION

This documentation describes how directory organized mailboxes work.
Please read C<Mail::Box-Overview> first.

At the moment, this object is extended by

=over 4

=item * MH

=item * Maildir

=back

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=default body_type 'Mail::Message::Body::Lines'
=default lock_file <folder>/.lock

=cut

sub init($)
{   my ($self, $args)    = @_;

    $args->{body_type} ||= sub {'Mail::Message::Body::Lines'};

    return undef
        unless $self->SUPER::init($args);

    my $directory        = $self->{MBD_directory}
       = (ref $self)->folderToDirectory($self->name, $self->folderdir);

    unless(-d $directory)
    {   $self->log(PROGRESS => "No directory $directory (yet)\n");
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
    {   warn "Folder $directory is write-protected.\n";
        $self->{MB_access} = 'r';
    }

    $self;
}

#-------------------------------------------

sub organization() { 'DIRECTORY' }

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method directory

Returns the directory related to this folder.

=examples

 print $folder->directory;

=cut

sub directory() { shift->{MBD_directory} }

#-------------------------------------------

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
