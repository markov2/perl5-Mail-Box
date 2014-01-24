
use strict;
package Mail::Box::Dbx;
use base 'Mail::Box::File';

use Mail::Box::Dbx::Message;
use Mail::Message::Head::Delayed;
use Mail::Message::Body::Delayed;

use Mail::Transport::Dbx 0.04;
use File::Basename 'dirname';

=chapter NAME

Mail::Box::Dbx - read Outlook Express folders

=chapter SYNOPSIS

 use Mail::Box::Dbx;
 my $folder = Mail::Box::Dbx->new(...);

=chapter DESCRIPTION

This documentation describes how to read from Outlook Express (dbx)
folders.  Even on Unix/Linux, you can access these folders to
read the data, or copy it to a different format.  Modifying of
xbd files is not supported.

These dbx folders are accessed using M<Mail::Transport::Dbx> which
is distributed via CPAN as separate package.  This C<MAil::Transport::Dbx>
module is based on the open source library named C<libpst>, which can
be found at L<http://alioth.debian.org/projects/libpst/>.  The library does
not support writing of dbx files, and therefore limits the possibilities
of this package.

=chapter METHODS

=c_method new %options

=default message_type M<Mail::Box::Dbx::Message>
=default access       always C<'r'>
=default folderdir    C<.>
=default folder       C<=Folders.dbx>
=default create       C<not implemented>
=default remove_when_empty C<not implemented>
=default save_on_exit C<not implemented>
=default write_policy C<not implemented>
=default lock_type    C<'NONE'>

=warning Dbx folders are read-only.

=cut

my $default_folder_dir    = '.';

sub init($)
{   my ($self, $args) = @_;
    $args->{folder}     ||= '=Folders.dbx';
    $args->{folderdir}  ||= $default_folder_dir;
    $args->{lock_type}  ||= 'NONE';

    $self->SUPER::init($args) or return;

    $self->log(WARNING => "Dbx folders are read-only.")
        if $self->writable;

    $self;
}

=ci_method create $foldername, %options
Creation is not supported for dbx folders.
=cut

sub create($@) {  shift->notImplemented }

=c_method foundIn [$foldername], %options
If no $foldername is specified, then the value of the C<folder> option
is taken.  A dbx folder is a file which name ends on C<.dbx> (case
insensitive).

=option  folder FOLDERNAME
=default folder undef
=cut

sub foundIn($@)
{   my $class = shift;
    my $name  = @_ % 2 ? shift : undef;
    my %args  = @_;

    $name   ||= $args{folder} or return;
    $name =~ m/\.dbx$/i;
}

sub writeMessages($) { shift->notImplemented }
sub appendMessages($) { shift->notImplemented }
sub type() { 'dbx' }

sub readMessages()
{   my ($self, %args) = @_;

    my @log      =  $self->logSettings;
    my @msgopts  =
     ( @log
     , folder     => $self
     , head_type  => $args{head_type}
     , field_type => $args{field_type}
     , trusted    => $args{trusted}
     );

    my $parser    = $self->parser
        or return;

    my $head_type = $self->{MB_head_delayed_type};
    my $body_type = $self->{MB_body_delayed_type};

    foreach my $record ($parser->emails)
    {   my $head    = $head_type->new(@log);

        my $message = $args{message_type}->new
          ( @msgopts
          , dbx_record => $record
          , head       => $head_type->new(@log)
          ) or next;

        $message->storeBody($body_type->new(@log, message => $message));
        $self->storeMessage($message);
    }

    $self;
}

sub updateMessages() { shift }

sub nameOfSubFolder($;$)
{   my $thing  = shift;
    my $name   = (shift). '.dbx';
    my $parent = @_ ? shift : ref $thing ? $thing->filename : undef;
    defined $parent ?  File::Spec->catfile(dirname($parent), $name) : $name;
}

=ci_method listSubFolders %options
It is advised to set the C<check> flag, because dbx folder often list
large amounts of folder names which do not really exist.  However, checking
does consume some time.
=cut

sub listSubFolders(@)
{   my ($thingy, %args)  = @_;
    my $self       = ref $thingy ? $thingy : $thingy->new;
    my $skip_empty = $args{skip_empty} || 0;
    my $check      = $args{check}      || 0;

    my $parser     = $self->parser
       or return;

    my @subs       = map { $_->name } $parser->subfolders;

    if($args{check})
    {    my $dir   = dirname $self->filename;
         @subs     = grep { -f File::Spec->catfile($dir, $_.'.dbx') } @subs;
    }

    return @subs unless $skip_empty;

    my @filled;
    foreach my $sub (@subs)
    {   my $f = $self->openSubFolder($sub, lock_type => 'NONE');
        push @filled, $f if defined $f && scalar($f->messages);
    }
    @filled;
}

#-------------------------------------------

=section Internals

=ci_method folderToFilename $foldername, $folderdir
Translate a folder name into a filename, using the
$folderdir value to replace a leading C<=>.
=cut

sub folderToFilename($$)
{   my ($thingy, $name, $folderdir) = @_;
    return $name if File::Spec->file_name_is_absolute($name);
    $name     =~ s#^=#$folderdir/#;
    $name;
}

=method parser
The parsing of messages is a combined job for the M<Mail::Transport::Dbx>
module (to get the right data) and M<read()>.  Asking for the parser
will provide the transporter object.  If asked more than once, each time
the same object will be returned.

=error Cannot read dbx folder file $filename.
=cut

sub parser()
{   my $self     = shift;
    return $self->{MBD_parser}
        if defined $self->{MBD_parser};

    my $filename = $self->filename;
    my $parser   = eval { Mail::Transport::Dbx->new($filename) };

    unless(defined $parser)
    {   $self->log(ERROR => "Cannot read dbx folder file $filename.");
        return undef;
    }

    $self->{MBD_parser} = $parser;
}

#-------------------------------------------

=section Error handling

=chapter DETAILS

=section How DBX folders work

DBX files are create by Outlook Express.  I can not tell you too much
about it, because me (as author) never use Windows or MicroSoft tools.
Still, it is possible to access some Outlook created folders from Unix.

The folder structure for dbx starts with a single C<Folders.dbx>
file.  This folder contains names of sub-folders.  Each folder can
either contain messages, or contains sub-folders.  Combinations are
not possible.

=section This implementation

The ol2mbox project (see L<http://sourceforge.net/project/ol2mbox/>)
has created a C<libdbx> which can read dbx files using nearly any
operating system.  You can simply transport a dbx file from Windows
to Unix/Linux and the read all the messages from it.

Tassilo von Parseval wrote a Perl wrapper around this C-library,
and distributes it as M<Mail::Transport::Dbx>.  Although it named in
one the MailBox namespaces, it is a separate product, because it
requires a C compiler.  Besides, the module will have its own life.

=section Converting DBX folders to MBOX

The title of this section is to attract your attension, but is does
not describe anything special related to DBX or MBOX: you can convert
any kind of mail folder into another with the following code.

=example converting folders

 my $from = Mail::Box::Dbx->new(folder => 'Folder.dbx')
    or exit;

 my $to   = Mail::Box::Mbox->new(folder => '/tmp/mbox',
    access => 'w', create => 1) or die;

 $from->copyTo($to);

=cut

1;
