
use strict;
use v5.6.0;

package Mail::Box::MH;
our @ISA     = 'Mail::Box';
our $VERSION = v0.1;

use Mail::Box;

use FileHandle;
use File::Copy;

=head1 NAME

Mail::Box::MH - Handle folders with a file per message.

=head1 SYNOPSIS

   use Mail::Box::MH;
   my $folder = new Mail::Box::MH folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

This manual-page describes Mail::Box::MH and Mail::Box::MH::*
packages.  Read Mail::Box::Manager and Mail::Box first.

Handle file-based folders, where each folder is represented by a
directory, and each message by a file in that directory.  Messages
are numbered.

The name of a folder may be an absolute or relative path.  You can also
preceed the foldername by C<=>, which means that it is relative to the
I<folderdir> as specified at C<new>.

=head2 Delayed loading

Folder-types which store their messages each in one file, together in
one directory, are bad for performance.  Consider that you want to know
the subjects of all messages.

Mail::Box::MH has two ways to try improve performance.  If you specify
C<keep_index> as option to the folder creation method C<new()>, then
all header-lines of all messages will be written into the specified
index-file (one file per folder).

If you do not use an index-file, then the only thing what the opening
of a folder does is invertoring which message-files exists.  Nothing
else.  For any request to any message, that message will be
autoloaded.
If the first request is for a header-line, then only the header is parsed,
and the message still left in the file.  For anything else, the whole
message is parsed.

The index-file is farmost best performing, but also in the second case,
performance can be ok.  When you have opened a huge folder, only a few
of those folders will be presented on the screen as index.  To present
the index we need the subject, hence we need to load the header of these
messages.  When you scroll through the index, header after header is
parsed.
If you want to read you messages in threads, you have a serious
performance problem: threads can only be displayed if all message
headers were read.  In this case, you should use an index-file.

=head1 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Create a new folder.  For the general options, see the manual of
L<Mail::Box>.  Other options:

=over 4

=item * lockfile => FILENAME

Which file shall be used for the dotlock-like locking mechanism.  When
you specify an absolute pathname, that will be used.  A relative path
will be related to the folder's directory.  The default is C<.lock>
 
=item * keep_index => BOOL

Keep an index-file in the specified file, one file per directory.  Using
an index-file will speed-up things considerably, because it avoids
that all message-files have to be read on the moment that you open the
folder.  When you open a folder, you need information like the the
subject of each message, and it is not pleasant to open all thousands
of messages to read them.

By default, index-files are OFF (false)

=item * index_filename => FILENAME

The FILENAME which is used in each directory to store the headers of
all mails.  The filename shall not contain a directory path (so: do not
use C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>)

The default filename is C<.index>.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{message_type}     ||= 'Mail::Box::MH::Message';
    $args->{dummy_type}       ||= 'Mail::Box::Message::Dummy';
    $args->{notreadhead_type} ||= 'Mail::Box::Message::NotReadHead';

    $self->SUPER::init($args);

    $self->registerHeaders('REAL') if $args->{keep_index};

    my $dirname                 = $self->{MB_dirname}
       = (ref $self)->folderToDirname($self->name, $self->folderdir);
    $self->{MB_lockfile}        = $args->{lockfile};
    $self->{MB_keep_index}      = $args->{keep_index}     || 0;
    $self->{MB_indexfile}       = $args->{index_filename} || '.index';

    # Check if we can write to the folder, if we need to.

    if($self->writeable && ! -w $dirname)
    {   if(-e $dirname)
        {   warn "Folder $dirname is write-protected.\n";
            $self->{MB_access} = 'r';
        }
        elsif(!mkdir $dirname)
        {   warn "Couldnot create folder in $dirname.\n";
            return undef;
        }
    }

    $self;
}

#-------------------------------------------

=item lockfileName

Returns the name of the lockfile, for the `dotlock' locking
mechanism.  For Mail::Box::MH folders, this defaults to
a file named C<.lock> in the folder directory.

The C<lockfile> option to C<new> overrules the name.  If that
name is relative, it will be taken relative to the folder-directory.

=cut

sub lockfileName
{  my $self     = shift;
   my $filename = $self->{MB_lockfile} || '.lock';
   return $filename if $filename =~ m!/!;

   $self->dirname . '/' . $filename;
}

#-------------------------------------------

=item readMessages

Read all messages from the folder.  This method is called at instantiation
of the folder, so do not call it yourself unless you have a very good
reason.

=cut

sub readMessages()
{   my $self = shift;
    $self->lock;

    # Prepare to scan for headers we want.  To speed things up, we create
    # a regular expression which will only fit exact on the right headers.
    # The only thing to do when the line fits is to lowercase the fieldname.

    my $mode = $self->registeredHeaders;
    my ($expect, $take, $take_headers);

    if(ref $mode)
    {   # If the user specified a list of fields, we prepare a regexp
        # which can match thid really fast.
        $expect = [ keys %$mode ];
        $mode   = 'SOME';
        $take   = '^(' . join('|', @$expect) . ')\:\s*(.*)$';
        $take_headers = qr/$take/i;
    }

    # Prepare the parser.

    my $parser     = $self->parser;
    my $delayed    = 0;

    # Select the messages from the directory (folder)
    # Each message is a file, where a sequence-number is
    # its name.

    my $dirname    = $self->dirname;

    opendir DIR, $dirname or return;
    my @messages = grep { -f && -r _ }
                       map { "$dirname/$_" }
                           sort {$a <=> $b}
                               grep /^\d+$/, readdir DIR;
    closedir DIR;

    # Retreive the information from the index-file if that
    # exists.  If so, this will speed-up things as lot.  We are
    # a bit anxious about changes to the folder which were made
    # by other programs or the user by hand.

    my @index = $self->readIndex;
    my $index_age = -M $self->indexFilename if @index;
    my %index = map { $_->get('x-mailbox-filename') => $_ } @index;

    foreach my $msgfile (@messages)
    {
        my $head;

        $head = $index{$msgfile}
            if exists $index{$msgfile} && -M $msgfile >= $index_age;

        my $size    = -s $msgfile;

        my @options =
          ( filename  => $msgfile
          , size      => $size
          );

        #
        # Read one message.
        #

        local $_;                       # protect global $_
        open MESSAGE, '<', $msgfile or return;

        # Read the header.

        my @header;
        while(<MESSAGE>)
        {   push @header, $_;
            last if /^\r?\n$/;
        }
        $self->unfoldHeaders(\@header);

        my $message;
        if(not $self->lazyExtract(\@header, undef, $size))
        {   #
            # Take the message immediately.
            #

            # Read the body, too.  For performance, this is added to the
            # header array.
            push @header, <MESSAGE>;

            $message = $self->{MB_message_type}->new
              ( message => $parser->parse_data(\@header)
              , @options
              );
        }
        elsif($mode eq 'SOME' || $mode eq 'ALL')
        {   #
            # Create delay-loaded message with some fields.
            #

            # Get all header lines for fast access.
            my $header = $self->{MB_notreadhead_type}->new(expect => $expect); 

            if($mode eq 'SOME')
            {   foreach (@header)
                {   $header->setField($1, $2) if $_ =~ $take_headers;
                }
            }
            else {  $header->setField(split ':', $_, 2) foreach @header }

            $message = $self->{MB_notparsed_type}->new
              ( head => $header
              , @options
              );

            $delayed++;
        }
        else
        {   #
            # Create a real header structure, but not yet the body.
            #

            $message = $self->{MB_notparsed_type}->new
              ( head => MIME::Head->new(\@header)->unfold
              , @options
              );

            $delayed++;
        }

        $self->addMessage($message) if $message;

        close MESSAGE;
    }

    # Release the folder.

    $self->{MB_source_mtime}  = (stat $dirname)[9];
    $self->{MB_delayed_loads} = $delayed;

    $self;
}
 
#-------------------------------------------

=item write

Write all messages to the folder-file.  Returns whether this
was successful.  If you want to write to a different file, you
first create a new folder, then move the messages, and then write
that file.

=cut

sub writeMessages(;$)
{   my Mail::Box::MH $self = shift;

    $self->lock;

    # Write each message.  Two things complicate things:
    #   1 - we may have a huge folder, which should not be on disk twice
    #   2 - we may have to replace a message, but it is unacceptable
    #       to remove the original before we are sure that the new version
    #       is on disk.

    my $writer = 0;
    foreach my $message ($self->messages)
    {
        # Remove deleted messages.
        if($message->deleted)
        {   unlink $message->filename;
            next;
        }

        my $new      = $self->dirname . '/' . $writer++;
        my $filename = $message->filename;

        if($message->modified)
        {   my $oldtmp   = "$filename.old";
            move($filename, $oldtmp);

            open NEW, '>', $new or die;
            $_->print(\*NEW);
            close NEW;

            unlink $oldtmp;
        }
        else
        {   move($filename, $new);
        }
    }

    #
    # Write the index-file.
    #

    $self->printIndex($self->messages);
    $self->unlock;

    1;
}

#-------------------------------------------

=item dirname

Returns the dirname related to this folder.

Example:
    print $folder->dirname;

=cut

sub dirname() { shift->{MB_dirname} }

#-------------------------------------------

=item defaultFolderDir [FOLDERDIR]

(class method)  Get or set the default directory where folders for this
type are located.

=cut

my $default_folder_dir = "$ENV{HOME}/.mh";

sub defaultFolderDir(;$)
{   my $class = shift;
    @_ ? ($default_folder_dir = shift) : $default_folder_dir;
}

#-------------------------------------------

=item folderToDirname FOLDERNAME, FOLDERDIR

(class method)  Translate a foldername into a filename, with use of the
FOLDERDIR to replace a leading C<=>.

=cut

sub folderToDirname($$)
{   my ($class, $name, $folderdir) = @_;
use Carp;
confess "folder to dirname @_.\n" unless $name;
    $name =~ /^=(.*)/ ? "$folderdir/$1" : $name;
}

#-------------------------------------------

=item indexFilename

Returns the index-file for a folder.  If the C<keep_index> option was
not used when the folder was read, this returns undef.

=cut

sub indexFilename()
{   my $self  = shift;
    return unless $self->{MB_keep_index};

    $self->dirname . '/' . $self->{MB_indexfile};
}

#-------------------------------------------

=item printIndex MESSAGE [,MESSAGE]

Write an index-file containing the specified messages, but only if the
user requested it: the C<keep_index> option of C<new()> must have been
specified.

=cut

sub printIndex(@)
{   my $self = shift;
    my $index = $self->indexFilename || return $self;

    open INDEX, '>', $index or return $self;

    foreach (@_)
    {   $_->printIndex(\*INDEX);
        print INDEX "\n";
    }

    close INDEX;
    $self;
}

#-------------------------------------------

=item readIndex

Read the index-file if it exists and the user has specified C<keep_index>
with the constructor (C<new>) of this folder.  If that option is not
specified, the C<readIndex> does not know under what name the index is
stored.

=cut

sub readIndex()
{   my $self  = shift;
    my $index = $self->indexFilename || return ();

    open INDEX, '<', $index or return ();

    my @index;
    my $type = $self->{MB_realhead_type};
    while(my $head = $type->read(\*INDEX))
    {   my $message = $self->{MB_notparsed_type}->new
              ( head => $head
              );
        push @index, $message;
    }

    close INDEX;
    @index;
}

#-------------------------------------------

=back

=head2 folder management methods

Read the Mail::Box manual for more details and more options
on each method.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

Autodetect if there is a Mail::Box::MH folder specified here.  The
FOLDERNAME specifies the name of the folder, as is specified by the
application.  The OPTIONS is a list of extra parameters to the request.

For this class, we use (if defined):

=over 4

=item * folderdir => DIRECTORY

=back

Example:
   Mail::Box::MH->foundIn
      ( '=markov'
      , folderdir => "$ENV{HOME}/.mh"
      );

=cut

sub foundIn($@)
{   my ($class, $name, %args) = @_;
    my $folderdir = $args{folderdir} || $class->defaultFolderDir;
    my $dirname   = $class->folderToDirname($name, $folderdir);
    -f "$dirname/1";
}

#-------------------------------------------

=item listFolders [OPTIONS]

List the folders in a certain directory.

=over 4

=item * folderdir => DIRECTORY

=item * check => BOOL

=item * skip_empty => BOOL

=back

=cut

sub listFolders(@)
{   my ($class, %args)  = @_;
    my $dir             = defined $args{folderdir}
                        ? $args{folderdir}
                        : $class->defaultFolderDir;

    $args{skip_empty} ||= 0;
    $args{check}      ||= 0;

    # Read the directories from the directory, to find all folders
    # stored here.  Some directories have to be removed because they
    # are created by all kinds of programs, but are no folders.

    return () unless -d $dir && opendir DIR, $dir;

    my @dirs = grep { !/^\d+$|^\./ && -d "$dir/$_" && -r _ }
                   readdir DIR;

    closedir DIR;

    @dirs = grep { -f "$_/1" } @dirs
       if $args{skip_empty};

    # Check if the files we want to return are really folders.

    return @dirs unless $args{check};

    grep { $class->foundIn("$dir/$_") } @dirs;
}

#-------------------------------------------

=item subFolders [OPTIONS]

Returns the subfolders to a folder.  Although file-type folders do not
have a natural form of sub-folders, we can simulate them.  The
C<subfolder_extention> option of the constructor (C<new()>) defines
how sub-folders can be recognized.

=over 4

=item * check => BOOL

=item * skip_empty => BOOL

=back

=cut

sub subFolders(@)
{  my $self = shift;

   (ref $self)->listFolders
     ( folderdir => $self->dirname
     , @_
     );
}

#-------------------------------------------

=item openSubFolder NAME [,OPTIONS]

Open (or create, if it does not exist yet) a new subfolder to an
existing folder.

Example:
    my $folder = Mail::Box::MH->new(folder => '=Inbox');
    my $sub    = $folder->openSubFolder('read');
 
=cut

sub openSubFolder($@)
{   my ($self, $name) = (shift, shift);
    my $dir = $self->dirname . '/' . $name;

    unless(-d $dir || mkdir $dir)
    {   warn "Cannot create subfolder $name for $self: $!\n";
        return;
    }

    $self->clone( folder => "$self/$name", @_ );
}

###
### Mail::Box::MH::Message::Runtime
###

package Mail::Box::MH::Message::Runtime;
use File::Copy;

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message::Runtime

This object contains methods which are part of as well delay-loaded
(not-parsed) as loaded messages, but not general for all folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in directory-based folders use the following extra options
for creation:

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{MBM_filename}   = $args->{filename};
    $self;
}

#-------------------------------------------

=item print TO

Write one message to a file-handle.  Unmodified messages are taken
from the folder-file where they were stored in.  Modified messages
are written as in memory.  Specify a file-handle to write TO
(defaults to STDOUT).

=cut

sub print()
{   my $self     = shift;
    my $out      = shift || \*STDOUT;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    if($self->modified && -r $filename)
    {   # Modified messages are printed as they were in memory.  This
        # may change the order and content of header-lines and (of
        # course) also the body.  If the message's original file
        # unexplainably disappeared, we also print the internally
        # stored message.

        $self->print($out);
    }
    else
    {   # Unmodified message are hard-copied from their file.
        copy($filename, $out);
    }

    1;
}

#-------------------------------------------

=item printIndex [FILEHANDLE]

Print the information of this message which is required to maintain
an index-file.  By default, this prints to STDOUT.

=cut

sub printIndex(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $head = $self->head;
    $head->add('X-MailBox-Filename', $self->filename);
    $head->print($out);
}

#-------------------------------------------

=item readIndex CLASS [,FILEHANDLE]

Read the headers of one message from the index into a CLASS
structure.  CLASS is (a sub-class of) a MIME::Head.  If no
FILEHANDLE is specified, the data is read from STDIN.

=cut

sub readIndex($;$)
{   my $self  = shift;
    shift->read(shift, shift || \*STDIN);
}

#-------------------------------------------

=item filename

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not read from a file.

=cut

sub filename() { shift->{MBM_filename} }

###
### Mail::Box::MH::Message
###

package Mail::Box::MH::Message;
our @ISA = qw(Mail::Box::MH::Message::Runtime Mail::Box::Message);

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message

This object extends a Mail::Box::Message with extra tools and facts
on what is special to messages in file-based folders, with respect to
messages in other types of folders.

=head2 PUBLIC INTERFACE

=over 4

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Message::init($args);
    $self->Mail::Box::MH::Message::Runtime::init($args);
    $self;
}

###
### Mail::Box::MH::Message::NotParsed
###

package Mail::Box::MH::Message::NotParsed;
our @ISA = qw/Mail::Box::MH::Message::Runtime
              Mail::Box::Message::NotParsed/;

use IO::InnerFile;

#-------------------------------------------

=back

=head1 Mail::Box::MH::Message::NotParsed

Not parsed messages stay in the file until the message is used.  Because
this folder structure uses many messages in the same file, the byte-locations
are remembered.

=head2 PUBLIC INTERFACE

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::MH::Message::Runtime::init(@_);
}

#-------------------------------------------

=item load

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

=cut

sub load($)
{   my ($self, $class) = @_;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    unless(open FILE, '<', $filename)
    {   warn "Cannot find folder $folder message $filename anymore.\n";
        return $self;
    }

    my $message = $folder->parser->parse(\*FILE);
    $message->head->unfold;

    $folder->{MB_delayed_loads}--;

    my $args    = { message  => $message };

    # I try to pass the change on, back to the caller.  The calling
    # routine has a handle to the non-parsed message structure.  We
    # may succeed in replacing that by the next assignment.
    # When the tric fails, it costs some performance, because autoloading
    # will continue to be called.  However, in that method, the retry
    # is detected and will immediately returns the right object.

    $_[0]       = (bless $self, $class)->delayedInit($args);
}

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 0.1

=cut

1;
