#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Dir;
use parent 'Mail::Box';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error warning/ ];

use Mail::Box::Dir::Message        ();
use Mail::Message::Body::Lines     ();
use Mail::Message::Body::File      ();
use Mail::Message::Body::Delayed   ();
use Mail::Message::Body::Multipart ();
use Mail::Message::Head            ();
use Mail::Message::Head::Delayed   ();

use File::Spec::Functions           qw/rel2abs/;

#--------------------
=chapter NAME

Mail::Box::Dir - handle folders with a file per message.

=chapter SYNOPSIS

  # Do not instantiate this object

=chapter DESCRIPTION

This documentation describes the way directory organized mailboxes work.
At the moment, this object is extended by

=over 4

=item * Mail::Box::MH
MH folders, which are represented by a directory containing files which
are sequentially numbered.

=item * Mail::Box::Maildir
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

=c_method new %options

=default body_type Mail::Message::Body::Lines
=default lock_file <folder>C</.lock>

=option  directory $directory
=default directory <derived from folder name>
For rare folder types, the $directory name may differ from the folder
name.

=warning Folder directory $directory is write-protected.
The folder $directory does already exist and is write protected, which may
interfere with the requested write access.  Change new(access) or the
permissions on the directory.

=error no directory $dir for folder of $type.
=warning folder directory $dir is write-protected
=cut

sub init($)
{	my ($self, $args)    = @_;

	$args->{body_type} //= sub { 'Mail::Message::Body::Lines' };
	$self->SUPER::init($args);

	my $class     = ref $self;
	my $directory = $self->{MBD_directory} = $args->{directory} || $self->directory;

		if(-d $directory) {;}
	elsif($args->{create} && $class->create($directory, %$args)) { ;}
	else
	{	error __x"no directory {dir} for folder of type.", dir => $directory, type => $class;
	}

	# About locking

	my $lf = $args->{lock_file} // '.lock';
	$self->locker->filename(rel2abs $lf, $directory);

	# Check if we can write to the folder, if we need to.

	if($self->writable && -e $directory && ! -w $directory)
	{	warning __x"folder directory {dir} is write-protected.", dir => $directory;
		$self->access('r');
	}

	$self;
}

#--------------------
=section Attributes
=cut

sub organization() { 'DIRECTORY' }

#--------------------
=section The folder

=method directory
Returns the directory related to this folder.

=example
  print $folder->directory;
=cut

sub directory()
{	my $self = shift;
	$self->{MBD_directory} ||= $self->folderToDirectory($self->name, $self->folderdir);
}

sub nameOfSubFolder($;$)
{	my ($thing, $name) = (shift, shift);
	my $parent = @_ ? shift : ref $thing ? $thing->directory : undef;
	defined $parent ? "$parent/$name" : $name;
}

#--------------------
=section Internals

=method folderToDirectory $foldername, $folderdir
(class method)  Translate a foldername into a filename, with use of the
$folderdir to replace a leading C<=>.
=cut

sub folderToDirectory($$)
{	my ($class, $name, $folderdir) = @_;
	my $dir = ($name =~ m#^=\/?(.*)# ? "$folderdir/$1" : $name);
	$dir =~ s!/$!!r;
}

sub storeMessage($)
{	my ($self, $message) = @_;
	$self->SUPER::storeMessage($message);
	my $fn = $message->filename or return $message;
	$self->{MBD_by_fn}{$fn} = $message;
}

=method messageInFile $filename
Returns the folder message which is found the indicated $filename.  This
may be useful when some external tool reports filename to be opened.
=cut

sub messageInFile($) { $_[0]->{MBD_by_fn}{$_[1]} }

=method readMessageFilenames $directory
Returns a list of all filenames which are found in this folder
$directory and represent a message.  The filenames are returned as
relative path.
=cut

sub readMessageFilenames() { $_[0]->notImplemented }

1;
