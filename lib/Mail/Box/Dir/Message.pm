#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Dir::Message;
use parent 'Mail::Box::Message';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error fault trace/ ];

use File::Copy       qw/move/;

#--------------------
=chapter NAME

Mail::Box::Dir::Message - one message in a directory organized folder

=chapter SYNOPSIS

  my $folder = new Mail::Box::MH ...
  my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::Dir::Message> is a base class for one message in a
directory organized folder; each message is stored in a separate file.
There are no objects of type C<Mail::Box::Dir::Message>, only extensions
are allowed to be created.

At the moment, three of these extended message types are implemented:

=over 4

=item * Mail::Box::MH::Message
which represents one message in a Mail::Box::MH folder.  MH folders are
very, very simple.... and hence not sophisticated nor fast.

=item * Mail::Box::Maildir::Message
which represents one message in a Mail::Box::Maildir folder.  Flags are
kept in the message's filename.  It is stateless, so you will never loose
a message.

=item * Mail::Box::Netzwert::Message
which represents one message in a Mail::Box::Netzwert folder.  As advantage,
it stores pre-parsed information in the message file.  As disadvantage: the
code is not GPLed (yet).

=back

=chapter METHODS

=section Constructors

=c_method new %options
Create a messages in a directory organized folder.

=option  filename $file
=default filename undef
The $file where the message is stored in.

=option  fix_header BOOLEAN
=default fix_header false
See M<Mail::Box::new(fix_headers)>.

=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);

	$self->filename($args->{filename}) if $args->{filename};
	$self->{MBDM_fix_header} = $args->{fix_header};
	$self;
}

#--------------------
=section Attributes

=method filename [$filename]
Returns the name of the file in which this message is actually stored.  This
will return undef when the message is not stored in a file.
=cut

sub filename(;$)
{	my $self = shift;
	@_ ? ($self->{MBDM_filename} = shift) : $self->{MBDM_filename};
}

=method fixHeader
Returns true when the folder is in fixing mode.
=cut

sub fixHeader() { $_[0]->{MBDM_fix_header} }

#--------------------
=section The message
=cut

sub print(;$)
{	my $self     = shift;
	my $out      = shift || select;

	return $self->SUPER::print($out)
		if $self->isModified;

	my $filename = $self->filename;
	if($filename && -r $filename)
	{	if(open my $in, '<:raw', $filename)
		{	local $_;
			print $out $_ while <$in>;
			close $in;
			return $self;
		}
	}

	$self->SUPER::print($out);
	1;
}

BEGIN { *write = \&print }  # simply alias

#--------------------
=section Internals
=cut

# Asking the filesystem for the size is faster counting (in
# many situations.  It even may be lazy.

sub size()
{	my $self = shift;

	unless($self->isModified)
	{	my $filename = $self->filename;
		if(defined $filename)
		{	my $size = -s $filename;
			return $size if defined $size;
		}
	}

	$self->SUPER::size;
}

sub diskDelete()
{	my $self = shift;
	$self->SUPER::diskDelete;

	my $filename = $self->filename;
	unlink $filename if $filename;
	$self;
}

=method parser
Create and return a parser for this message (-file).
=cut

sub parser()
{	my $self   = shift;

	Mail::Box::Parser->new(
		filename => $self->filename,
		mode     => 'r',
		fix_header_errors => $self->fixHeader,
	);
}

=method loadHead
This method is called by the autoloader when the header of the message
is needed.
=cut

sub loadHead()
{	my $self     = shift;
	my $head     = $self->head;
	$head->isDelayed or return $head;

	my $folder   = $self->folder;
	$folder->lazyPermitted(1);

	my $parser   = $self->parser or return;
	$self->readFromParser($parser);
	$parser->stop;

	$folder->lazyPermitted(0);

	trace "Loaded delayed head.";
	$self->head;
}

=method loadBody
This method is called by the autoloader when the body of the message
is needed.

=error unable to read delayed head for message $msgid.
Mail::Box tries to be I<lazy> with respect to parsing messages.  When a
directory organized folder is opened, only the filenames of messages are
collected.  At first use, the messages are read from their file.  Apperently,
a message is used for the first time here, but has disappeared or is
unreadible for some other reason.

=error unable to read delayed body for message $msgid.
For some reason, the header of the message could be read, but the body
cannot.  Probably the file has disappeared or the permissions were
changed during the progress of the program.

=cut

sub loadBody()
{	my $self     = shift;

	my $body     = $self->body;
	$body->isDelayed or return $body;

	my $parser   = $self->parser;
	my $msgid    = $self->messageId;

	my $head     = $self->head;
	if($head->isDelayed)
	{	$head = $self->readHead($parser)
			or error __x"unable to read delayed head for message {msgid}.", msgid => $msgid;

		trace "Loaded delayed head for $msgid.";
		$self->head($head);
	}
	else
	{	my ($begin, $end) = $body->fileLocation;
		$parser->filePosition($begin);
	}

	my $newbody  = $self->readBody($parser, $head)
		or error __x"unable to read delayed body for message {msgid}.", msgid => $msgid;

	$parser->stop;
	trace "Loaded delayed body for $msgid";
	$self->storeBody($newbody->contentInfoFrom($head));
}

=method create $filename
Create the message in the specified file.  If the message already has
a filename and is not modified, then a move is tried.  Otherwise the
message is printed to the file.  If the $filename already exists for
this message, nothing is done.  In any case, the new $filename is set
as well.

=fault cannot write message to $file: $!
When a modified or new message is written to disk, it is first written
to a temporary file in the folder directory.  For some reason, it is
impossible to create this file.

=fault failed to rename file $from to $to: $!
When a modified or new message is written to disk, it is first written
to a temporary file in the folder directory.  Then, the new file is
moved to replace the existing file.  Apparently, the latter fails.

=cut

sub create($)
{	my ($self, $filename) = @_;

	my $old = $self->filename || '';
	return $self if $filename eq $old && !$self->isModified;

	# Write the new data to a new file.

	my $new = $filename . '.new';
	open my $newfh, '>:raw', $new
		or fault __x"cannot write message to {file}", file => $new;

	$self->write($newfh);
	$newfh->close;

	unlink $old if $old;

	move $new, $filename
		or error __x"failed to rename file {from} to {to}", from => $new, to => $filename;

	$self->modified(0);

	# Do not affect flags for Maildir (and some other) which keep it
	# in there.  Flags will be processed later.
	$self->Mail::Box::Dir::Message::filename($filename);
	$self;
}

1;
