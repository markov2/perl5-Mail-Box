#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::File;
use parent 'Mail::Box';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error fault trace warning/ ];

use Mail::Box::File::Message       ();
use Mail::Message::Body::Lines     ();
use Mail::Message::Body::File      ();
use Mail::Message::Body::Delayed   ();
use Mail::Message::Body::Multipart ();
use Mail::Message::Head            ();

use File::Copy            qw/move/;
use File::Spec::Functions qw/file_name_is_absolute catfile/;
use File::Basename        qw/dirname basename/;
use Scalar::Util          qw/blessed/;
#use POSIX                qw/:unistd_h/;

my $windows;
BEGIN { $windows = $^O =~ m/mswin32/i }

#--------------------
=chapter NAME

Mail::Box::File - handle file-based folders

=chapter SYNOPSIS

=chapter DESCRIPTION

C<Mail::Box::File> is the base-class for all file-based folders: folders
which bundle multiple messages into one single file.  Usually, these
messages are separated by a special line which indicates the start of
the next one.

=chapter METHODS

=c_method new %options

=default folderdir C<$ENV{HOME}.'/Mail'>
=default lock_file <foldername><lock-extension>

=default message_type Mail::Box::File::Message

=option  lock_extension $file|STRING
=default lock_extension C<'.lock'>
When the dotlock locking mechanism is used, the lock is created with a
hardlink to the folder file.  For C<Mail::Box::File> type of folders, this
filename is by default named as the folder-file itself followed by
C<.lock>.  For example: the C<Mail/inbox> folder file will have a hardlink
made as C<Mail/inbox.lock>.

You may specify an absolute $file, a relative (to the folder's
directory) filename, or an extension (preceded by a dot).  So valid
examples are:

  .lock                  # appended to the folder's filename
  my_own_lockfile.test   # full filename, same dir
  /etc/passwd            # somewhere else

When the program runs with less privileges (as normal user), often the
default inbox folder can not be locked with the lockfile name which is
produced by default.

=option  write_policy 'REPLACE'|'INPLACE'|undef
=default write_policy undef
Sets the default write policy, as default for a later call to
M<write(policy)>.  With undef, the best policy is autodetected.

=option  body_type CLASS|CODE
=default body_type <see description>
The default P<body_type> option for C<File> folders, which will cause
messages larger than 10kB to be stored in files and smaller files
in memory, is implemented like this:

  sub determine_body_type($$)
  {   my $head = shift;
      my $size = shift || 0;
      'Mail::Message::Body::' . ($size > 10000 ? 'File' : 'Lines');
  }

=warning folder $name file $file is write-protected.
The folder is opened writable or for appending via M<new(access)>,
but the operating system does not permit writing to the $file.  The folder
will be opened read-only.

=error folder file $name does not exist.
=error cannot get a lock on $type folder $name.
=cut

my $default_folder_dir = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';

sub _default_body_type($$)
{	my $size = shift->guessBodySize || 0;
	'Mail::Message::Body::'.($size > 100000 ? 'File' : 'Lines');
}

sub init($)
{	my ($self, $args) = @_;
	$args->{folderdir} ||= $default_folder_dir;
	$args->{body_type} ||= \&_default_body_type;
	$args->{lock_file} ||= '--';   # to be resolved later
	$self->SUPER::init($args);

	my $class    = ref $self;
	my $filename = $self->{MBF_filename} = $self->folderToFilename($self->name, $self->folderdir);

	if(-e $filename) {;}    # Folder already exists
	elsif($args->{create} && $class->create($args->{folder}, %$args)) {;}
	else
	{	error __x"folder file {file} does not exist.", file => $filename;
	}

	$self->{MBF_policy}  = $args->{write_policy};

	# Lock the folder.

	my $locker   = $self->locker;

	my $lockfile = $locker->filename;
	if($lockfile eq '--')            # filename to be used not resolved yet
	{	my $lockdir   = $filename =~ s!/([^/]*)$!!r;
		my $extension = $args->{lock_extension} || '.lock';
		my $fn
		  = file_name_is_absolute($extension) ? $extension
		  : $extension =~ m!^\.!  ? "$filename$extension"
		  :    catfile($lockdir, $extension);

		$locker->filename($fn);
	}

	$locker->lock
		or error __x"cannot get a lock on {type} folder {name}.", type => $class, name => $self->name;

	# Check if we can write to the folder, if we need to.
	if($self->writable && ! -w $filename)
	{	warning __x"folder {name} file {file} is write-protected.", name => $self->name, file => $filename;
		$self->access('r');
	}

	# Start parser if reading is required.
	$self->parser if $self->access =~ m/r/;
	$self;
}

=ci_method create $foldername, %options

=fault cannot create directory $dir for folder $name: $!
While creating a file-organized folder, at most one level of directories
is created above it.  Apparently, more levels of directories are needed,
or the operating system does not allow you to create the directory.

=fault cannot create folder file $file: $!
The file-organized folder file cannot be created for the indicated reason.
In common cases, the operating system does not grant you write access to
the directory where the folder file should be stored.

=cut

sub create($@)
{	my ($thingy, $name, %args) = @_;
	my $class     = ref $thingy      || $thingy;
	my $folderdir = $args{folderdir} || $default_folder_dir;
	my $subext    = $args{subfolder_extension};    # not always available
	my $filename  = $class->folderToFilename($name, $folderdir, $subext);

	return $class if -f $filename;

	my $dir       = dirname $filename;
	if(-f $dir && defined $subext)
	{	$dir      .= $subext;
		$filename  = catfile $dir, basename $filename;
	}

	-d $dir || mkdir $dir, 0755
		or fault __x"cannot create directory {dir} for folder $name: $!", dir => $dir, name => $name;

	$class->moveAwaySubFolder($filename, $subext)
		if -d $filename && defined $subext;

	open my $create, '>:raw', $filename
		or fault __x"cannot create folder file {file}", file => $filename;

	trace "Created folder $name in $filename.";
	$create->close or return;
	$class;
}

#--------------------
=section Attributes

=method filename
Returns the filename for this folder, which may be an absolute or relative
path to the file.

=examples
  print $folder->filename;
=cut

sub filename() { $_[0]->{MBF_filename} }

sub foundIn($@)
{	my $class = shift;
	my $name  = @_ % 2 ? shift : undef;
	my %args  = @_;
	$name   ||= $args{folder} or return;

	my $folderdir = $args{folderdir} || $default_folder_dir;
	my $filename  = $class->folderToFilename($name, $folderdir);

	-f $filename;
}

sub organization() { 'FILE' }

sub size()
{	my $self = shift;
	$self->isModified ? $self->SUPER::size : -s $self->filename;
}

sub close(@)
{	my $self = $_[0];            # be careful, we want to set the calling
	undef $_[0];                 #    ref to undef, as the SUPER does.
	shift;

	my $rc = $self->SUPER::close(@_);

	if(my $parser = delete $self->{MBF_parser}) { $parser->stop }

	$rc;
}

#--------------------
=section The folder

=c_method appendMessages %options

Appending messages to a file based folder which is not opened is a little
risky.  In practice, this is often done without locking the folder.  So,
another application may write to the folder at the same time... :(
Hopefully, all goes fast enough that the chance on collision is small.

All %options of M<Mail::Box::Mbox::new()> can be supplied.

=option  lock_type ...
=default lock_type C<NONE>
See M<Mail::Box::new(lock_type)> for possible values.

=error cannot append messages to folder file $file: $!
Appending messages to a not-opened file-organized folder may fail when the
operating system does not allow write access to the file at hand.
=cut

sub appendMessages(@)
{	my $class  = shift;
	my %args   = @_;

	my @messages
	  = exists $args{message}  ? $args{message}
	  : exists $args{messages} ? @{$args{messages}}
	  :   return ();

	my $folder   = $class->new(lock_type => 'NONE', @_, access => 'w+')
		or return ();

	my $filename = $folder->filename;
	open my $out, '>>', $filename
		or fault __x"cannot append messages to folder file {file}.", file => $filename;

	my $msgtype = $class.'::Message';
	my @coerced;

	foreach my $msg (@messages)
	{	my $coerced = $msg->isa($msgtype) ? $msg : $msgtype->coerce($msg->can('clone') ? $msg->clone : $msg);
		$coerced->write($out);
		push @coerced, $coerced;
	}

	my $ok = $folder->close;
	$out->close && $ok
		or return ();

	@coerced;
}

#--------------------
=section Internals

=method parser
Create a parser for this mailbox.  The parser stays alive as long as
the folder is open.
=cut

sub parser()
{	my $self   = shift;
	return $self->{MBF_parser} if defined $self->{MBF_parser};

	my $source = $self->filename;
	my $mode   = $self->access || 'r';
	$mode      = 'r+' if $mode eq 'rw' || $mode eq 'a';

	my $parser = $self->{MBF_parser} = Mail::Box::Parser->new(
		filename          => $source,
		mode              => $mode,
		trusted           => $self->isTrusted,
		fix_header_errors => $self->fixHeaders,
	);
	$parser->pushSeparator('From ');
	$parser;
}

sub readMessages(@)
{	my ($self, %args) = @_;

	$self->messageCreateOptions(
		$args{message_type},
		folder     => $self,
		head_type  => $args{head_type},
		field_type => $args{field_type},
		trusted    => $args{trusted},
	);

	$self->updateMessages;
}

=method updateMessages %options
For file based folders, the file handle stays open until the folder
is closed.  Update is therefore rather simple: move to the end
of the last known message, and continue reading...
=cut

sub updateMessages(@)
{	my ($self, %args) = @_;
	my $parser   = $self->parser or return;

	# On a directory, simulate an empty folder with only subfolders.
	my $filename = $self->filename;
	return $self if -d $filename;

	if(my $last  = $self->message(-1))
	{	(undef, my $end) = $last->fileLocation;
		$parser->filePosition($end);
	}

	my ($type, @msgopts) = $self->messageCreateOptions;
	my $count    = 0;

	while(1)
	{	my $message = $type->new(@msgopts);
		$message->readFromParser($parser) or last;
		$self->storeMessage($message);
		$count++;
	}

	trace "found $count new messages in $filename";
	$self;
}

=method messageCreateOptions [$type, $config]
Returns a key-value list of options to be used each time a new message
is read from a file.  The list is preceded by the $type of message which
has to be created.

This data is used by M<readMessages()> and M<updateMessages()>.  With
$type and $config, a new configuration is set.
=cut

sub messageCreateOptions(@)
{	my ($self, @options) = @_;
	if(@options)
	{	blessed $_ && (ref $_) =~ m/^Mail::/ && weaken $_ for @options;
		$self->{MBF_create_options} = \@options;
	}

	@{$self->{MBF_create_options}};
}

=method moveAwaySubFolder $directory, $extension
The $directory is renamed by appending the $extension, which defaults to C<".d">,
to make place for a folder file on that specific location.  false is
returned if this failed.

=fault cannot move away sub-folder $dir: $!
=cut

sub moveAwaySubFolder($$)
{	my ($self, $dir, $extension) = @_;

	move $dir, $dir.$extension
		or fault __x"cannot move away sub-folder {dir}", dir => $dir;

	$self;
}

sub delete(@)
{	my $self = shift;
	$self->SUPER::delete(@_);
	unlink $self->filename;
}

=method write %options

=option  policy 'REPLACE'|'INPLACE'|undef
=default policy undef
In what way will the mail folder be updated.  If not specified during the
write, the value of the M<new(write_policy)> at folder creation is taken.

Valid values:

=over 4
=item * C<REPLACE>
First a new folder is written in the same directory as the folder which has
to be updated, and then a call to move will throw away the old immediately
replacing it by the new.

Writing in C<REPLACE> module is slightly optimized: messages which are not
modified are copied from file to file, byte by byte.  This is much
faster than printing the data which is will be done for modified messages.

=item * C<INPLACE>
The original folder file will be opened read/write.  All message which where
not changed will be left untouched, until the first deleted or modified
message is detected.  All further messages are printed again.

=item * undef
As default, or when undef is explicitly specified, first C<REPLACE> mode
is tried.  Only when that fails, an C<INPLACE> update is performed.

=back

C<INPLACE> will be much faster than C<REPLACE> when applied on large
folders, however requires the C<truncate> function to be implemented on
your operating system (at least available for recent versions of Linux,
Solaris, Tru64, HPUX).  It is also dangerous: when the program is interrupted
during the update process, the folder is corrupted.  Data may be lost.

However, in some cases it is not possible to write the folder with
C<REPLACE>.  For instance, the usual incoming mail folder on UNIX is
stored in a directory where a user can not write.  Of course, the
C<root> and C<mail> users can, but if you want to use this Perl module
with permission of a normal user, you can only get it to work in C<INPLACE>
mode.  Be warned that in this case folder locking via a lockfile is not
possible as well.

=warning cannot remove folder $name file $filename: $!
Writing an empty folder will usually cause that folder to be removed,
which fails for the indicated reason.  M<new(remove_when_empty)>
controls whether the empty folder will removed; setting it to false
(C<0>) may be needed to avoid this message.

=error unable to update folder $name.
When a folder is to be written, both replace and inplace write policies are
tried,  If both fail, the whole update fails.  You may see other, related,
error messages to indicate the real problem.

=error file $name too short to get write message $msgnr ($size < $expect)
Mail::Box is lazy: it tries to leave messages in the folders until they
are used, which saves time and memory usage.  When this message appears,
something is terribly wrong: some lazy message are needed for updating the
folder, but they cannot be retrieved from the original file anymore.  In
this case, messages can be lost.

This message does appear regularly on Windows systems when using the
'replace' write policy.  Please help to find the cause, probably something
to do with Windows incorrectly handling multiple filehandles open in the
same file.

=fault cannot replace $to by $from to update folder $name: $!
The replace policy wrote a new folder file to update the existing, but
was unable to give the final touch: replacing the old version of the
folder file for the indicated reason.

=cut

sub writeMessages($)
{	my ($self, $args) = @_;

	my $filename = $self->filename;
	if( ! @{$args->{messages}} && $self->removeEmpty)
	{	unlink $filename
			or warning __x"cannot remove folder {name} file {file}: {rc}", name => $self->name, file => $filename, rc => $!;
		return $self;
	}

	my $policy = exists $args->{policy} ? $args->{policy} : $self->{MBF_policy};
	$policy  ||= '';

	my $success
	  = ! -e $filename       ? $self->_write_new($args)
	  : $policy eq 'INPLACE' ? $self->_write_inplace($args)
	  : $policy eq 'REPLACE' ? $self->_write_replace($args)
	  : $self->_write_replace($args) ? 1
	  :    $self->_write_inplace($args);

	$success
		or error __x"unable to update folder {name}.", name => $self->name;

#   $self->parser->restart;
	$self;
}

sub _write_new($)
{	my ($self, $args) = @_;

	my $filename = $self->filename;
	open my $new, ">:raw", $filename
		or return 0;

	my $msgs = $args->{messages};
	$_->write($new) for @$msgs;
	$new->close or return 0;

	trace "Wrote new folder $self with ".@$msgs."msgs.";
	1;
}

# First write to a new file, then replace the source folder in one
# move.  This is much slower than inplace update, but it is safer,
# The folder is always in the right shape, even if the program is
# interrupted.

sub _write_replace($)
{	my ($self, $args) = @_;

	my $filename = $self->filename;
	my $tmpnew   = $self->tmpNewFolder($filename);

	open my $new, '>:raw', $tmpnew   or return 0;
	open my $old, '<:raw', $filename or return 0;

	my ($reprint, $kept) = (0,0);

	foreach my $message ( @{$args->{messages}} )
	{
		my $newbegin = $new->tell;
		my $oldbegin = $message->fileLocation;

		if($message->isModified)
		{	$message->write($new);
			$message->moveLocation($newbegin - $oldbegin) if defined $oldbegin;
			$reprint++;
			next;
		}

		my ($begin, $end) = $message->fileLocation;
		my $need = $end-$begin;

		$old->seek($begin, 0);
		my $whole;
		my $size = $old->read($whole, $need);

		$size == $need
			or error __x"file {name} too short to get write message {msgnr} ({size} < {expect})",
				msgnr => $message->seqnr, size => $size, expect => $need;

		$new->print($whole);
		$new->print($Mail::Message::crlf_platform ? "\r\n" : "\n");

		$message->moveLocation($newbegin - $oldbegin);
		$kept++;
	}

	my $ok = $new->close;
	$old->close && $ok
		or return 0;

	if($windows)
	{	# Windows does not like to move to existing filenames
		unlink $filename;

		# Windows cannot move to files which are opened.
		$self->parser->closeFile;
	}

	unless(move $tmpnew, $filename)
	{	unlink $tmpnew;
		fault __x"cannot replace {to} by {from} to update folder {name}", to => $filename, from => $tmpnew, name => $self->name;
	}

	trace "folder $self replaced ($kept, $reprint)";
	1;
}

# Inplace is currently very poorly implemented.  From the first
# location where changes appear, all messages are rewritten.

sub _write_inplace($)
{	my ($self, $args) = @_;

	my @messages = @{$args->{messages}};
	my $last;

	my ($msgnr, $kept) = (0, 0);
	while(@messages)
	{	my $next = $messages[0];
		last if $next->isModified || $next->seqnr!=$msgnr++;
		$last    = shift @messages;
		$kept++;
	}

	if(@messages==0 && $msgnr==$self->messages)
	{	trace "No changes to be written to $self.";
		return 1;
	}

	$_->body->load for @messages;

	my $mode     = $^O eq 'MSWin32' ? '>>:raw' : '+<:raw';
	my $filename = $self->filename;
	open my $old, $mode, $filename or return 0;

	# Chop the folder after the messages which does not have to change.

	my $end = defined $last ? ($last->fileLocation)[1] : 0;

	$end =~ m/(.*)/;  # untaint, only required by perl5.6.1
	$end = $1;

	unless($old->truncate($end))
	{	# truncate impossible: try replace writing
		$old->close;
		return 0;
	}

	unless(@messages)
	{	# All further messages only are flagged to be deleted
		$old->close or return 0;
		trace "Folder $self shortened in-place ($kept kept)";
		return 1;
	}

	# go to the end of the truncated output file.
	$old->seek(0, 2);

	# Print the messages which have to move.
	my $printed = @messages;
	foreach my $message (@messages)
	{	my $oldbegin = $message->fileLocation;
		my $newbegin = $old->tell;
		$message->write($old);
		$message->moveLocation($newbegin - $oldbegin);
	}

	$old->close or return 0;
	trace "Folder $self updated in-place ($kept, $printed)";
	1;
}

=ci_method folderToFilename $foldername, $folderdir, [$subext]
Translate a $foldername into a filename, using the $folderdir value
to replace a leading C<=>.  The optional $subext is only used for MBOX
folders.
=cut

sub folderToFilename($$;$)
{	my ($thing, $name, $folderdir) = @_;

	substr $name, 0, 1, $folderdir
		if substr $name, 0, 1 eq '=';

	$name;
}

sub tmpNewFolder($) { $_[0]->filename . '.tmp' }

#--------------------
=section DETAILS

=subsection File based folders

File based folders maintain a folder (a set of messages) in one
single file.  The advantage is that your folder has only one
single name, which speeds-up access to all messages at once.

The disadvantage over directory based folder (see Mail::Box::Dir)
is that you have to construct some means to keep all message apart,
for instance by adding a message separator, and this will cause
problems.  Where access to all messages at once is faster in file
based folders, access to a single message is (much) slower, because
the whole folder must be read.

=cut

1;
