#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::MH;
use parent 'Mail::Box::Dir';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error fault trace/ ];

use Mail::Box::MH::Index   ();
use Mail::Box::MH::Message ();
use Mail::Box::MH::Labels  ();

use File::Spec::Functions  qw/rel2abs/;
use File::Basename         qw/basename/;

# Since MailBox 2.052, the use of File::Spec is reduced to the minimum,
# because it is too slow.  The '/' directory separators do work on
# Windows too.

#--------------------
=chapter NAME

Mail::Box::MH - handle MH folders

=chapter SYNOPSIS

  use Mail::Box::MH;
  my $folder = Mail::Box::MH->new(folder => $ENV{MAIL}, ...);

=chapter DESCRIPTION

This documentation describes how MH mailboxes work, and what you
can do with the MH folder object C<Mail::Box::MH>.

=chapter METHODS

=c_method new %options

=default folderdir C<$ENV{HOME}/.mh>
=default lock_file <index_file>

=option  keep_index BOOLEAN
=default keep_index false
Keep an index file of the specified mailbox, one file per directory.
Using an index file will speed up things considerably, because it avoids
reading all the message files the moment that you open the folder.  When
you open a folder, you can use the index file to retrieve information such
as the subject of each message, instead of having to read possibly
thousands of messages.

=option  index_filename $file
=default index_filename <foldername>C</.index>
The $file which is used in each directory to store the headers of all
mails. The filename shall not contain a directory path. (e.g. Do not use
C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>.)

=option  index $object
=default index undef
You may specify an $object of a type which extends Mail::Box::MH::Index
(at least implements a C<get()> method), as alternative for an index file
reader as created by C<Mail::Box::MH>.

=option  labels_filename $file
=default labels_filename <foldername>C</.mh_sequence>
In MH-folders, messages can be labeled, for instance based on the
sender or whether it is read or not.  This status is kept in a
$file which is usually called C<.mh_sequences>, but that name can
be overruled with this flag.

=option  labels $object
=default labels undef
You may specify an $object of a type which extends Mail::Box::MH::Labels
(at least implements the C<get()> method), as alternative for labels file
reader as created by C<Mail::Box::MH>.

=option  index_type $class
=default index_type Mail::Box::MH::Index

=option  labels_type $class
=default labels_type Mail::Box::MH::Labels

=cut

my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.mh" : '.';

sub init($)
{	my ($self, $args) = @_;
	$args->{folderdir}     ||= $default_folder_dir;
	$args->{lock_file}     ||= $args->{index_filename};

	$self->SUPER::init($args);

	my $folderdir            = $self->folderdir;
	my $directory            = $self->directory;
	-d $directory or return;

	# About the index

	$self->{MBM_keep_index}  = $args->{keep_index} || 0;
	$self->{MBM_index}       = $args->{index};
	$self->{MBM_index_type}  = $args->{index_type} || 'Mail::Box::MH::Index';

	my $ifn = $args->{index_filename} //= '.index';
	$self->{MBM_index_filename} = rel2abs $ifn, $directory;

	# About labels

	$self->{MBM_labels}      = $args->{labels};
	$self->{MBM_labels_type} = $args->{labels_type} || 'Mail::Box::MH::Labels';

	my $lfn = $args->{labels_filename} //= '.mh_sequences';
	$self->{MBM_labels_filename} = rel2abs $lfn, $directory;

	$self;
}

=ci_method create $foldername, %options

=fault cannot create MH folder $name: $!
For some reason, it is impossible to create the folder.  Check the permissions
and the $name of the folder.  Does the path to the directory to be created
exist?
=cut

sub create($@)
{	my ($thingy, $name, %args) = @_;
	my $class     = ref $thingy      || $thingy;
	my $folderdir = $args{folderdir} || $default_folder_dir;
	my $directory = $class->folderToDirectory($name, $folderdir);

	return $class if -d $directory;

	mkdir $directory, 0700
		or fault __x"cannot create MH folder {name}", name => $name;

	trace "Created folder $name.";
	$class;
}

#--------------------
=section Attributes
=cut

sub type() {'mh'}

sub foundIn($@)
{	my $class = shift;
	my $name  = @_ % 2 ? shift : undef;
	my %args  = @_;
	my $folderdir = $args{folderdir} || $default_folder_dir;
	my $directory = $class->folderToDirectory($name, $folderdir);

	-d $directory or return 0;
	-f "$directory/1" and return 1;  # cheap

	# More thorough search required in case some numbered messages
	# disappeared (lost at fsck or copy?)

	opendir my $dh, $directory or return 0;
	foreach (readdir $dh)
	{	m/^[0-9]+$/ or next;   # Look for filename which is a number.
		closedir $dh;
		return 1;
	}

	closedir $dh;
	0;
}

sub listSubFolders(@)
{	my ($class, %args) = @_;
	my $dir;
	if(ref $class)
	{	$dir   = $class->directory;
		$class = ref $class;
	}
	else
	{	my $folder    = $args{folder}    || '=';
		my $folderdir = $args{folderdir} || $default_folder_dir;
		$dir   = $class->folderToDirectory($folder, $folderdir);
	}

	$args{skip_empty} ||= 0;
	$args{check}      ||= 0;

	# Read the directories from the directory, to find all folders
	# stored here.  Some directories have to be removed because they
	# are created by all kinds of programs, but are no folders.

	-d $dir && opendir my $dh, $dir or return ();
	my @dirs = grep { !/^\d+$|^\./ && -d "$dir/$_" } readdir $dh;
	closedir $dh;

	# Skip empty folders.  If a folder has sub-folders, then it is not
	# empty.
	if($args{skip_empty})
	{	my @not_empty;

		foreach my $subdir (@dirs)
		{	if(-f "$dir/$subdir/1")
			{	# Fast found: the first message of a filled folder.
				push @not_empty, $subdir;
				next;
			}

			opendir my $dh, "$dir/$subdir" or next;
			my @entities = grep !/^\./, readdir $dh;
			closedir $dh;

			if(grep /^\d+$/, @entities)   # message 1 was not there, but
			{	push @not_empty, $subdir; # other message-numbers exist.
				next;
			}

			foreach (@entities)
			{	-d "$dir/$subdir/$_" or next;
				push @not_empty, $subdir;
				last;
			}
		}

		@dirs = @not_empty;
	}

	# Check if the files we want to return are really folders.

	@dirs = map { m/(.*)/ && $1 ? $1 : () } @dirs;   # untaint
	$args{check} or return @dirs;

	grep $class->foundIn("$dir/$_"), @dirs;
}

#-------------
=section The folder
=cut

sub topFolderWithMessages() { 1 }

=c_method appendMessages %options
Append a message to a folder which is not open.

=error cannot append message without lock on $folder.
It is impossible to append one or more messages to the folder which is
not opened, because locking it fails.  The folder may be in use by
an other application, or you may need to specify some lock related
options (see M<new()>).
=cut

sub appendMessages(@)
{	my $class  = shift;
	my %args   = @_;

	my @messages
	  = exists $args{message}  ? $args{message}
	  : exists $args{messages} ? @{$args{messages}}
	  :   return ();

	my $self     = $class->new(@_, access => 'r')
		or return ();

	my $locker   = $self->locker;
	$locker->lock
		or error __x"cannot append message without lock on {folder}.", folder => $self->name;

	my $msgnr    = $self->highestMessageNumber +1;

	my $directory= $self->directory;
	foreach my $message (@messages)
	{	my $filename = "$directory/$msgnr";
		$message->create($filename);
		$msgnr++;
	}

	$self->labels->append(@messages);
	$self->index->append(@messages);

	$locker->unlock;
	$self->close(write => 'NEVER');

	@messages;
}

#--------------------
=section Sub-folders

=method openSubFolder
=fault cannot create directory $dir for subfolder $name: $!
=cut

sub openSubFolder($)
{	my ($self, $name) = @_;

	my $subdir = $self->nameOfSubFolder($name);
	-d $subdir || mkdir $subdir, 0755
		or fault __x"cannot create directory {dir} for subfolder {name}", dir => $subdir, name => $name;

	$self->SUPER::openSubFolder($name, @_);
}

#--------------------
=section Internals

=method highestMessageNumber
Returns the highest number which is used in the folder to store a file.
This method may be called when the folder is read (then this number can
be derived without file-system access), but also when the folder is not
read (yet).
=cut

sub highestMessageNumber()
{	my $self = shift;

	return $self->{MBM_highest_msgnr}
		if exists $self->{MBM_highest_msgnr};

	my $directory = $self->directory;

	opendir my $dh, $directory or return;
	my @messages = sort {$a <=> $b} grep /^[0-9]+$/, readdir $dh;
	closedir $dh;

	$messages[-1];
}

=method index
Create a index reader/writer object.
=cut

sub index()
{	my $self  = shift;
	$self->{MBM_keep_index} or return ();

	$self->{MBM_index} //= $self->{MBM_index_type}->new(filename => $self->{MBM_index_filename});
}

=method labels
Create a label reader/writer object.
=cut

sub labels()
{	my $self = shift;
	$self->{MBM_labels} //= $self->{MBM_labels_type}->new(filename => $self->{MBM_labels_filename});
}

sub readMessageFilenames
{	my ($self, $dirname) = @_;

	opendir my $dh, $dirname or return;

	# list of numerically sorted, untainted filenames.
	my @msgnrs = sort {$a <=> $b}
		map { /^(\d+)$/ && -f "$dirname/$1" ? $1 : () } readdir $dh;

	closedir $dh;
	@msgnrs;
}

sub readMessages(@)
{	my ($self, %args) = @_;

	my $directory = $self->directory;
	-d $directory or return;

	my $locker    = $self->locker;
	$locker->lock or return;

	my @msgnrs    = $self->readMessageFilenames($directory);

	my $index     = $self->{MBM_index};
	unless($index)
	{	$index = $self->index;
		$index->read if $index;
	}

	my $labels = $self->{MBM_labels};
	unless($labels)
	{	$labels = $self->labels;
		$labels->read if $labels;
	}

	my $body_type   = $args{body_delayed_type};
	my $head_type   = $args{head_delayed_type};

	foreach my $msgnr (@msgnrs)
	{	my $msgfile = "$directory/$msgnr";

		my $head;
		$head       = $index->get($msgfile) if $index;
		$head     ||= $head_type->new;

		my $message = $args{message_type}->new(
			head       => $head,
			filename   => $msgfile,
			folder     => $self,
			fix_header => $self->fixHeaders,
		);

		my $labref  = $labels ? $labels->get($msgnr) : ();
		$message->label(seen => 1, $labref ? @$labref : ());

		$message->storeBody($body_type->new(message => $message));
		$self->storeMessage($message);
	}

	$self->{MBM_highest_msgnr}  = $msgnrs[-1];
	$locker->unlock;
	$self;
}

sub delete(@)
{	my $self = shift;
	$self->SUPER::delete(@_);

	my $dir = $self->directory;
	opendir my $dh, $dir or return 1;
	untaint $dh;

	# directories (subfolders) are not removed, as planned
	unlink "$dir/$_" for readdir $dh;
	closedir $dh;

	rmdir $dir;    # fails when there are subdirs (without recurse)
}


=method writeMessages %options

=option  renumber BOOLEAN
=default renumber true
Permit renumbering of message.  By default this is true, but for some
unknown reason, you may be thinking that messages should not be renumbered.

=error cannot write folder $name without lock.
It is impossible to get a lock on the folder, which means that the changes
can not be made.  You may need to tune the lock related options which
are available at folder creation.
=cut

sub writeMessages($)
{	my ($self, $args) = @_;
	my $renumber = exists $args->{renumber} ? $args->{renumber} : 1;

	# Write each message.  Two things complicate life:
	#   1 - we may have a huge folder, which should not be on disk twice
	#   2 - we may have to replace a message, but it is unacceptable
	#       to remove the original before we are sure that the new version
	#       is on disk.

	my $locker    = $self->locker;
	$locker->lock
		or error __x"cannot write folder {name} without lock.", name => $self->name;

	my $directory = $self->directory;
	my @messages  = @{$args->{messages}};

	my $writer    = 0;
	foreach my $message (@messages)
	{	my $filename = $message->filename;

		my $newfile;
		if($renumber || !$filename)
		{	$newfile = $directory . '/' . ++$writer;
		}
		else
		{	$newfile = $filename;
			$writer  = basename $filename;
		}

		$message->create($newfile);
	}

	# Write the labels- and the index-file.

	my $labels = $self->labels;
	$labels->write(@messages) if $labels;

	my $index  = $self->index;
	$index->write(@messages)  if $index;

	$locker->unlock;

	# Remove an empty folder.  This is done last, because the code before
	# in this method will have cleared the contents of the directory.
	# If something else is still in the directory, this will fail, but I don't mind.
	rmdir $directory
		if !@messages && $self->removeEmpty;

	$self;
}

#--------------------
=chapter DETAILS

=section How MH folders work

MH-type folders use a directory to store the messages of one folder.  Each
message is stored in a separate file.  This seems useful, because changes
in a folder change only a few of these small files, in contrast with
file-based folders where changes in a folder cause rewrites of huge
folder files.

However, MH-based folders perform very bad if you need header information
of all messages.  For instance, if you want to have full knowledge about
all message-threads (see Mail::Box::Thread::Manager) in the folder, it
requires to read all header lines in all message files.  And usually, reading
your messages in threads is desired.

So, each message is written in a separate file.  The filenames are
numbers, which count from C<1>.  Next to these message files, a
directory may contain a file named C<.mh_sequences>, storing labels which
relate to the messages.  Furthermore, a folder-directory may contain
sub-directories, which are seen as sub-folders.

=section This implementation

This implementation supports the C<.mh-sequences> file and sub-folders.
Next to this, considerable effort it made to avoid reading each message-file.
This should boost performance of the MailBox distribution over other
Perl-modules which are able to read folders.

Folder types which store their messages each in one file, together in
one directory, are bad for performance.  Consider that you want to know
the subjects of all messages, while browser through a folder with your
mail-reading client.  This would cause all message-files to be read.

Mail::Box::MH has two ways to try improve performance.  You can use
an index-file, and use on delay-loading.  The combination performs even
better.  Both are explained in the next sections.

=section An index-file

If you specify M<new(keep_index)>, then all header-lines of all messages
from the folder which have been read once, will also be written into
one dedicated index-file (one file per folder).  The default filename
is C<.index>

However, index-files are not supported by any other reader which supports
MH (as far as I know).  If you read the folders with such I client, it
will not cause unrecoverable conflicts with this index-file, but at most
be bad for performance.

If you do not (want to) use an index-file, then delay-loading may
save your day.

=cut

1;
