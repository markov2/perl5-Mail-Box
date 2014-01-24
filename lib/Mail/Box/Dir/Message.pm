
use strict;
use warnings;

package Mail::Box::Dir::Message;
use base 'Mail::Box::Message';

use File::Copy qw/move/;
use IO::File;

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

=item * M<Mail::Box::MH::Message>
which represents one message in a M<Mail::Box::MH> folder.  MH folders are
very, very simple.... and hence not sophisticated nor fast.

=item * M<Mail::Box::Maildir::Message>
which represents one message in a M<Mail::Box::Maildir> folder.  Flags are
kept in the message's filename.  It is stateless, so you will never loose
a message.

=item * M<Mail::Box::Netzwert::Message>
which represents one message in a M<Mail::Box::Netzwert> folder.  As advantage,
it stores pre-parsed information in the message file.  As disadvantage: the
code is not GPLed (yet).

=back

=chapter METHODS

=c_method new %options

Create a messages in a directory organized folder.

=option  filename FILENAME
=default filename undef

The file where the message is stored in.

=option  fix_header BOOLEAN
=default fix_header C<false>

See M<Mail::Box::new(fix_headers)>.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->filename($args->{filename})
        if $args->{filename};

    $self->{MBDM_fix_header} = $args->{fix_header};
    $self;
}

#-------------------------------------------

=section The message

=cut

#-------------------------------------------

sub print(;$)
{   my $self     = shift;
    my $out      = shift || select;

    return $self->SUPER::print($out)
        if $self->isModified;

    my $filename = $self->filename;
    if($filename && -r $filename)
    {   if(open my $in, '<:raw', $filename)
        {    local $_;
             print $out $_ while <$in>;
             close $in;
             return $self;
        }
    }

    $self->SUPER::print($out);

    1;
}

#-------------------------------------------

BEGIN { *write = \&print }  # simply alias

#-------------------------------------------

=method filename [$filename]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub filename(;$)
{   my $self = shift;
    @_ ? ($self->{MBDM_filename} = shift) : $self->{MBDM_filename};
}

#-------------------------------------------

=section Internals

=cut

# Asking the filesystem for the size is faster counting (in
# many situations.  It even may be lazy.

sub size()
{   my $self = shift;

    unless($self->isModified)
    {   my $filename = $self->filename;
        if(defined $filename)
        {   my $size = -s $filename;
            return $size if defined $size;
        }
    }

    $self->SUPER::size;
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->SUPER::diskDelete;

    my $filename = $self->filename;
    unlink $filename if $filename;
    $self;
}

#-------------------------------------------

=method parser

Create and return a parser for this message (-file).

=error Cannot create parser for $filename.

For some reason (the previous message have told you already) it was not possible
to create a message parser for the specified filename.

=cut

sub parser()
{   my $self   = shift;

    my $parser = Mail::Box::Parser->new
      ( filename => $self->{MBDM_filename}
      , mode     => 'r'
      , fix_header_errors => $self->{MBDM_fix_header}
      , $self->logSettings
      );

    unless($parser)
    {   $self->log(ERROR => "Cannot create parser for $self->{MBDM_filename}.");
        return;
    }

    $parser;
}

#-------------------------------------------

=method loadHead

This method is called by the autoloader when the header of the message
is needed.

=cut

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    my $folder   = $self->folder;
    $folder->lazyPermitted(1);

    my $parser   = $self->parser or return;
    $self->readFromParser($parser);
    $parser->stop;

    $folder->lazyPermitted(0);

    $self->log(PROGRESS => 'Loaded delayed head.');
    $self->head;
}

#-------------------------------------------

=method loadBody

This method is called by the autoloader when the body of the message
is needed.

=error Unable to read delayed head.

Mail::Box tries to be I<lazy> with respect to parsing messages.  When a
directory organized folder is opened, only the filenames of messages are
collected.  At first use, the messages are read from their file.  Apperently,
a message is used for the first time here, but has disappeared or is
unreadible for some other reason.

=error Unable to read delayed body.

For some reason, the header of the message could be read, but the body
cannot.  Probably the file has disappeared or the permissions were
changed during the progress of the program.

=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $head     = $self->head;
    my $parser   = $self->parser or return;

    if($head->isDelayed)
    {   $head = $self->readHead($parser);
        if(defined $head)
        {   $self->log(PROGRESS => 'Loaded delayed head.');
            $self->head($head);
        }
        else
        {   $self->log(ERROR => 'Unable to read delayed head.');
            return;
        }
    }
    else
    {   my ($begin, $end) = $body->fileLocation;
        $parser->filePosition($begin);
    }

    my $newbody  = $self->readBody($parser, $head);
    $parser->stop;

    unless(defined $newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody->contentInfoFrom($head));
}

#-------------------------------------------

=method create $filename
Create the message in the specified file.  If the message already has
a filename and is not modified, then a move is tried.  Otherwise the
message is printed to the file.  If the $filename already exists for
this message, nothing is done.  In any case, the new $filename is set
as well.

=error Cannot write message to $filename: $!
When a modified or new message is written to disk, it is first written
to a temporary file in the folder directory.  For some reason, it is
impossible to create this file.

=error Failed to move $new to $filename: $!
When a modified or new message is written to disk, it is first written
to a temporary file in the folder directory.  Then, the new file is
moved to replace the existing file.  Apparently, the latter fails.

=cut

sub create($)
{   my ($self, $filename) = @_;

    my $old = $self->filename || '';
    return $self if $filename eq $old && !$self->isModified;

    # Write the new data to a new file.

    my $new     = $filename . '.new';
    my $newfile = IO::File->new($new, 'w');
    $self->log(ERROR => "Cannot write message to $new: $!"), return
        unless $newfile;

    $self->write($newfile);
    $newfile->close;

    # Accept the new data
# maildir produces warning where not expected...
#   $self->log(WARNING => "Failed to remove $old: $!")
#       if $old && !unlink $old;

    unlink $old if $old;

    $self->log(ERROR => "Failed to move $new to $filename: $!"), return
         unless move($new, $filename);

    $self->modified(0);

    # Do not affect flags for Maildir (and some other) which keep it
    # in there.  Flags will be processed later.
    $self->Mail::Box::Dir::Message::filename($filename);

    $self;
}

#-------------------------------------------

1;
