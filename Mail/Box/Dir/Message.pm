
use strict;
use warnings;

package Mail::Box::Dir::Message;
use base 'Mail::Box::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::Dir::Message - one message in a directory-organized folder

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A Mail::Box::Dir::Message is a base class for one message in a directory
organized folder; each message is stored in a separate file.  There are
no objects of type Mail::Box::Dir::Message, only extensions are allowed to
be created.

At the moment, two of these extended message types are implemented:

=over 4

=item * Mail::Box::MH::Message

which represents one message in a Mail::Box::MH folder.

=item * Mail::Box::Maildir::Message

which represents one message in a Mail::Box::Maildir folder.

=back

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

Create a messages in a directory organized folder.

=option  filename FILENAME
=default filename undef

The file where the message is stored in.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->filename($args->{filename})
        if $args->{filename};

    $self;
}

#-------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

sub print(;$)
{   my $self     = shift;
    my $out      = shift || select;

    return $self->SUPER::print($out)
        if $self->modified;

    my $filename = $self->filename;
    if($filename && -r $filename)
    {   copy($filename, $out);
        return $self;
    }

    $self->SUPER::print($out);

    1;
}

#-------------------------------------------

=method filename [FILENAME]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub filename(;$)
{   my $self = shift;
    @_ ? $self->{MBDM_filename} = shift : $self->{MBDM_filename};
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

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

=cut

sub parser()
{   my $self   = shift;

    my $parser = Mail::Box::Parser->new
      ( filename  => $self->{MBDM_filename}
      , mode      => 'r'
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
    $self->storeBody($newbody);
}

#-------------------------------------------

=method create FILENAME

Create the message in the specified file.  If the message already has
a filename and is not modified, then a move is tried.  Otherwise the
message is printed to the file.  If the FILENAME already exists for
this message, nothing is done.  In any case, the new FILENAME is set
as well.

=cut

sub create($)
{   my ($self, $filename) = @_;

    my $old = $self->filename || '';
    return $self if $filename eq $old && !$self->modified;

    # Write the new data to a new file.

    my $new     = $filename . '.new';
    my $newfile = IO::File->new($new, 'w');
    $self->log(ERROR => "Cannot write message to $new: $!"), return
        unless $newfile;

    $self->print($newfile);
    $newfile->close;

    # Accept the new data
# maildir produces warning where not expected...
#   $self->log(WARNING => "Failed to remove $old: $!")
#       if $old && !unlink $old;

    unlink $old if $old;

    $self->log(ERROR => "Failed to move $new to $filename: $!"), return
         unless move($new, $filename);

    $self->modified(0);
    $self->Mail::Box::Dir::Message::filename($filename);

    $self;
}

#-------------------------------------------

1;
