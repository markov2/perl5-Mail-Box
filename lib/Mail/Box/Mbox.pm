#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Mbox;
use parent 'Mail::Box::File';

use strict;
use warnings;

use Log::Report      'mail-box';

use Mail::Box::Mbox::Message ();

use File::Spec::Functions    qw/catdir catfile/;

#--------------------
=chapter NAME

Mail::Box::Mbox - handle folders in Mbox format

=chapter SYNOPSIS

  use Mail::Box::Mbox;
  my $folder = Mail::Box::Mbox->new(folder => $ENV{MAIL}, ...);

=chapter DESCRIPTION

This documentation describes how Mbox mailboxes work, and also describes
what you can do with the Mbox folder object Mail::Box::Mbox.

=chapter METHODS

=c_method new %options

=default message_type Mail::Box::Mbox::Message

=option  subfolder_extension STRING
=default subfolder_extension C<'.d'>
Mbox folders do not support sub-folders.  However, this module can
simulate sub-directories if the user wants it to.  When a subfolder of
folder C<xyz> is created, we create a directory which is called C<xyz.d>
to contain them.  This extension C<.d> can be changed using this option.
=cut

our $default_folder_dir    = exists $ENV{HOME} ? $ENV{HOME} . '/Mail' : '.';
our $default_sub_extension = '.d';

sub init($)
{	my ($self, $args) = @_;
	$self->{MBM_sub_ext} = $args->{subfolder_extension} || $default_sub_extension;
	$self->SUPER::init($args);
}

=ci_method create $foldername, %options

=option  subfolder_extension STRING
=default subfolder_extension undef
If a directory is found on the location of the folder to be created, this
STRING is used to extend that directory name with.  This will cause the
directory to be seen as sub-folder for the created folder.  This argument
is passed to M<folderToFilename()>.
=cut

sub create($@)
{	my ($thingy, $name, %args) = @_;
	my $class = ref $thingy    || $thingy;
	$args{folderdir}           ||= $default_folder_dir;
	$args{subfolder_extension} ||= $default_sub_extension;

	$class->SUPER::create($name, %args);
}

#--------------------
=section Attributes
=method subfolderExtension
=cut

sub subfolderExtension() { $_[0]->{MBM_sub_ext} }

sub delete(@)
{	my $self = shift;
	$self->SUPER::delete(@_);

	my $subfdir = $self->filename . $default_sub_extension;
	rmdir $subfdir;   # may fail, when there are still subfolders (no recurse)
}

sub writeMessages($)
{	my ($self, $args) = @_;
	$self->SUPER::writeMessages($args);

	if($self->removeEmpty)
	{	# Can the sub-folder directory be removed?  Don't mind if this
		# doesn't work: probably no subdir or still something in it.  This
		# is a rather blunt approach...
		rmdir $self->filename . $self->subfolderExtension;
	}

	$self;
}

sub type() {'mbox'}

#--------------------
=section Sub-folders

=ci_method listSubFolders %options
=option  subfolder_extension STRING
=default subfolder_extension <from object>
When the method is called on an open folder, the extension defined by it is
used to detect sub-folders by default.  Otherwise, C<'.d'> is taken.
=cut

sub listSubFolders(@)
{	my ($thingy, %args)  = @_;
	my $class      = ref $thingy || $thingy;

	my $skip_empty = $args{skip_empty} || 0;
	my $check      = $args{check}      || 0;
	my $folder     = $args{folder}     // '=';
	my $folderdir  = $args{folderdir}  // $default_folder_dir;
	my $extension  = $args{subfolder_extension};

	my $dir;
	if(ref $thingy)   # Mail::Box::Mbox
	{	$extension ||= $thingy->subfolderExtension;
		$dir = $thingy->filename;
	}
	else
	{	$extension ||= $default_sub_extension;
		$dir = $class->folderToFilename($folder, $folderdir, $extension);
	}

	my $real  = -d $dir ? $dir : "$dir$extension";
	opendir my $dh, $real or return ();

	# Some files have to be removed because they are created by all
	# kinds of programs, but are no folders.

	my @entries = grep !m/\.lo?ck$|^\./, readdir $dh;
	closedir $dh;

	# Look for files in the folderdir.  They should be readable to
	# avoid warnings for usage later.  Furthermore, if we check on
	# the size too, we avoid a syscall especially to get the size
	# of the file by performing that check immediately.

	my %folders;  # hash to immediately un-double names.

	foreach my $b (@entries)
	{	my $entry = catfile $real, $b;
		if( -f $entry )
		{	next if $args{skip_empty} && ! -s _;
			next if $args{check} && !$class->foundIn($entry);
			$folders{$b}++;
		}
		elsif( -d _ )
		{	# Directories may create fake folders.
			if($args{skip_empty})
			{	opendir my $dh, $entry or next;
				my @sub = grep !/^\./, readdir $dh;
				closedir $dh;
				@sub or next;
			}

			my $folder = $b =~ s/$extension$//r;
			$folders{$folder}++;
		}
	}

	map +(m/(.*)/ && $1), keys %folders;   # untained names
}

sub openRelatedFolder(@)
{	my $self = shift;
	$self->SUPER::openRelatedFolder(subfolder_extension => $self->subfolderExtension, @_);
}

#--------------------
=section Internals

=ci_method folderToFilename $foldername, $folderdir, [$extension]
Translate a folder name into a filename, using the
$folderdir value to replace a leading C<=>.  If no $extension is specified and
this method is called as instance method, new(subfolder_extension) is used.
Otherwise, the extension default to C<'.d'>.
=cut

sub folderToFilename($$;$)
{	my ($thingy, $name, $folderdir, $extension) = @_;
	$extension ||= ref $thingy ? $thingy->subfolderExtension : $default_sub_extension;

	$name     =~ s#^=#$folderdir/#;
	my @parts = split m!/!, $name;

	my $real  = shift @parts;
	$real     = '/' if $real eq '';

	if(@parts)
	{	my $file  = pop @parts;
		$real = catdir  $real.(-d $real ? '' : $extension), $_ for @parts;
		$real = catfile $real.(-d $real ? '' : $extension), $file;
	}

	$real;
}

=c_method foundIn [$foldername], %options
If no $foldername is specified, then the value of the P<folder> option
is taken.  A mbox folder is a file which starts with a separator
line: a line with C<'From '> as first characters.  Blank lines which
start the file are ignored, which is not for all MUA's acceptable.

=option  folder $name
=default folder undef

=option  subfolder_extension STRING
=default subfolder_extension <from object>
=cut

sub foundIn($@)
{	my $class = shift;
	my $name  = @_ % 2 ? shift : undef;
	my %args  = @_;
	$name   ||= $args{folder} or return;

	my $folderdir = $args{folderdir} || $default_folder_dir;
	my $extension = $args{subfolder_extension} || $default_sub_extension;
	my $filename  = $class->folderToFilename($name, $folderdir, $extension);

	if(-d $filename)
	{	# Maildir and MH Sylpheed have a 'new' sub-directory
		return 0 if -d catdir $filename, 'new';
		if(opendir my $dir, $filename)
		{	my @f = grep !/^\./, readdir $dir;   # skip . .. and hidden
			return 0 if @f && ! grep /\D/, @f;              # MH
			closedir $dir;
		}

		return 0                                             # Other MH
			if -f "$filename/.mh_sequences";

		return 1;      # faked empty Mbox sub-folder (with subsub-folders?)
	}

	return 0 unless -f $filename;
	return 1 if -z $filename;               # empty folder is ok

	open my $file, '<:raw', $filename or return 0;
	local $_;
	while(<$file>)
	{	next if /^\s*$/;                    # skip empty lines
		$file->close;
		return substr($_, 0, 5) eq 'From '; # found Mbox separator?
	}

	return 1;
}

#--------------------
=chapter DETAILS

=section How MBOX folders work

MBOX folders store many messages in one file.  Each message begins with a
line which starts with the string C<From >.  Lines inside a message which
accidentally start with C<From> are, in the file, preceded by `E<gt>'. This
character is stripped when the message is read.

In this respect must be noted that the format of the MBOX files is not
strictly defined.  The exact content of the separator lines differ between
Mail User Agents (MUA's).  Besides, some MUAs (like mutt) forget to encode
the C<From > lines within message bodies, breaking other parsers....

=section Simulation of sub-folders

MBOX folders do not have a sub-folder concept as directory based folders
do, but this MBOX module tries to simulate them.  In this implementation
a directory like

  Mail/subject1/

is taken as an empty folder C<Mail/subject1>, with the folders in that
directory as sub-folders for it.  You may also use

  Mail/subject1
  Mail/subject1.d/

where C<Mail/subject1> is the folder, and the folders in the
C<Mail/subject1.d> directory are used as sub-folders.  If your situation
is similar to the first example and you want to put messages in that empty
folder, the directory is automatically (and transparently) renamed, so
that the second situation is reached.

=cut

1;
