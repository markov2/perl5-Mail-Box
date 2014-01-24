use strict;
use warnings;

package Mail::Box::Manager;
use base 'Mail::Reporter';

use Mail::Box;

use List::Util   'first';
use Scalar::Util 'weaken';

# failed compilation will not complain a second time
# so we need to keep track.
my %require_failed;

=chapter NAME

Mail::Box::Manager - manage a set of folders

=chapter SYNOPSIS

 use Mail::Box::Manager;
 my $mgr     = new Mail::Box::Manager;

 # Create folder objects.
 my $folder   = $mgr->open(folder => $ENV{MAIL});
 my $message1 = $folder->message(0);
 $mgr->copyMessage('Draft', $message);

 my @messages = $folder->message(0,3);
 $mgr->moveMessage('Outbox', @messages, create => 1 );
 $mgr->close($folder);

 # Create thread-detectors (see M<Mail::Box::Thread::Manager>)
 my $t       = $mgr->threads($inbox, $outbox);

 my $threads = $mgr->threads(folder => $folder);
 foreach my $thread ($threads->all)
 {   $thread->print;
 }

 $mgr->registerType(mbox => 'Mail::Box::MyType');

=chapter DESCRIPTION

The manager keeps track on a set of open folders and a set of message-thread
supporting objects.  You are not obliged to use this object (you can
directly create a M<Mail::Box::Mbox> if you prefer), but you will create
more portable and safer code if you do use it.

=chapter METHODS

=c_method new $args

=option  folder_types NEW-TYPE | ARRAY-OF-NEW-TYPES
=default folder_types <all standard types>
Add one or more new folder types to the list of known types.  The order is
important: when you open a file without specifying its type, the
manager will start trying the last added list of types, in order.

Each TYPE is specified as an array which contains name, class, and
defaults for options which overrule the usual defaults.  You may specify
folder-specific defaults as OPTIONS.  They override the settings of
the manager.

=option  autodetect TYPE|ARRAY-OF-TYPES
=default autodetect C<undef>
Select only a subset of the folder types which are implemented by MailBox
to be detected automatically.  This may improve the auto-detection of
folder types.  Normally, all folder types will be tried when a folder's
name is incorrect, but this option limits the types which are checked
and therefore may respond faster.

=option  default_folder_type NAME|CLASS
=default default_folder_type C<'mbox'>
Specifies the default folder type for newly created folders.  If this
option is not specified, the most recently registered type is used (see
M<registerType()> and the M<new(folder_types)> option.

=option  folderdir DIRECTORY
=default folderdir C<[ '.' ]>
The default directory, or directories, where folders are
located. The C<Mail::Box::Manager> can autodetect the existing folder-types.
There may be different kinds of folders opened at the same time, and
messages can be moved between those types, although that may result in
a loss of information depending on the folder types.

=option  folderdirs [DIRECTORIES]
=default folderdirs <synonym for C<folderdir>>

=cut

my @basic_folder_types =
  ( [ mbox    => 'Mail::Box::Mbox'    ]
  , [ mh      => 'Mail::Box::MH'      ]
  , [ maildir => 'Mail::Box::Maildir' ]
  , [ pop     => 'Mail::Box::POP3'    ]
  , [ pop3    => 'Mail::Box::POP3'    ]
  , [ pop3s   => 'Mail::Box::POP3s'   ]
  , [ imap    => 'Mail::Box::IMAP4'   ]
  , [ imap4   => 'Mail::Box::IMAP4'   ]
  );

my @managers;  # usually only one, but there may be more around :(

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    # Register all folder-types.  There may be some added later.

    my @new_types;
    if(exists $args->{folder_types})
    {   @new_types = ref $args->{folder_types}[0]
                   ? @{$args->{folder_types}}
                   : $args->{folder_types};
    }

    my @basic_types = reverse @basic_folder_types;
    if(my $basic = $args->{autodetect})
    {   my %types = map { ( $_ => 1) } (ref $basic ? @$basic : ($basic));
        @basic_types = grep { $types{$_->[0]} } @basic_types;
    }

    $self->{MBM_folder_types} = [];
    $self->registerType(@$_) foreach @new_types, @basic_types;

    $self->{MBM_default_type} = $args->{default_folder_type} || 'mbox';

    # Inventory on existing folder-directories.
    $self->{MBM_folderdirs} = [ ];
    if(exists $args->{folderdir})
    {   my @dirs = $args->{folderdir};
        @dirs = @{$dirs[0]} if ref $dirs[0];
        push @{$self->{MBM_folderdirs}}, @dirs;
    }

    if(exists $args->{folderdirs})
    {   my @dirs = $args->{folderdirs};
        @dirs = @{$dirs[0]} if ref $dirs[0];
        push @{$self->{MBM_folderdirs}}, @dirs;
    }
    push @{$self->{MBM_folderdirs}}, '.';

    $self->{MBM_folders} = [];
    $self->{MBM_threads} = [];

    push @managers, $self;
    weaken $managers[-1];

    $self;
}

#-------------------------------------------

=section Attributes

=method registerType $type, $class, %options

With C<registerType> you can register one $type of folders.  The $class
is compiled automatically, so you do not need to C<use> them in your own
modules.  The $type is just an arbitrary name.

The added types are prepended to the list of known types, so they are
checked first when a folder is opened in autodetect mode.

=example

 $manager->registerType(mbox => 'Mail::Box::Mbox',
     save_on_exit => 0, folderdir => '/tmp');

=cut

sub registerType($$@)
{   my ($self, $name, $class, @options) = @_;
    unshift @{$self->{MBM_folder_types}}, [$name, $class, @options];
    $self;
}

#-------------------------------------------

=method folderdir
In list context, this returns all folderdirs specified.  In SCALAR
context only the first.
=cut

sub folderdir()
{   my $dirs = shift->{MBM_folderdirs} or return ();
    wantarray ? @$dirs : $dirs->[0];
}

#-------------------------------------------

=method folderTypes
Returns the list of currently defined folder types.

=example
 print join("\n", $manager->folderTypes), "\n";

=cut

sub folderTypes()
{   my $self = shift;
    my %uniq;
    $uniq{$_->[0]}++ foreach @{$self->{MBM_folder_types}};
    sort keys %uniq;
}

#-------------------------------------------

=method defaultFolderType
Returns the default folder type, some class name.
=cut

sub defaultFolderType()
{   my $self = shift;
    my $name = $self->{MBM_default_type};
    return $name if $name =~ m/\:\:/;  # obviously a class name

    foreach my $def (@{$self->{MBM_folder_types}})
    {   return $def->[1] if $def->[0] eq $name || $def->[1] eq $name;
    }

    undef;
}

#-------------------------------------------

=section Manage open folders

=method open [$foldername], %options

Open a folder which name is specified as first parameter or with
the option flag C<folder>.  The folder type is autodetected unless
the C<type> is specified.

C<open> carries options for the manager which are described here, but
may also have additional options for the folder type.  For a
description of the folder options, see the options to the constructor
M<Mail::Box::new()> for each type of mail box.

=option  create BOOLEAN
=default create <false>

Create the folder if it does not exist. By default, this is not done.
The C<type> option specifies which type of folder is created.

=option  folder NAME|URL
=default folder C<$ENV{MAIL}>

Which folder to open, specified by NAME or special URL.
The URL format is composed as

 type://username:password@hostname:port/foldername

Like real URLs, all fields are optional and have smart defaults, as long
as the string starts with a known folder type.  Far
from all folder types support all these options, but at least they are
always split-out.  Be warned that special characters in the password should
be properly url-encoded.

When you specify anything which does not match the URL format, it is
passed directly to the C<new> method of the folder which is opened.

=option  folderdir DIRECTORY
=default folderdir C<'.'>

The directory where the folders are usually stored.

=option  type FOLDERTYPENAME|FOLDERTYPE
=default type <first, usually C<mbox>>
Specify the type of the folder.  If you do not specify this option while
opening a folder for reading, the manager checks all registered folder
types in order for the ability to open the folder. If you open a new
folder for writing, then the default will be the most recently registered
type. (If you add more than one type at once, the first of the list is
used.)

=option authenticate  TYPE|ARRAY-OF-TYPES|'AUTO'
=default authenticate C<'AUTO'>
The TYPE of authentication to be used, or a list of TYPES which the
client prefers.  The server may provide preferences as well, and that
order will be kept.  This option is only supported by a small subset of
folder types, especially by POP and IMAP.

=examples opening folders via the manager

 my $jack  = $manager->open(folder => '=jack',
    type => 'mbox');

 my $rcvd  = $manager->open('myMail',
    type => 'Mail::Box::Mbox', access => 'rw');

 my $inbox = $manager->open('Inbox')
    or die "Cannot open Inbox.\n";

 my $pop   = 'pop3://myself:secret@pop3.server.com:120/x';
 my $send  = $manager->open($url);

 my $send  = $manager->open(folder => '/x',
   type => 'pop3', username => 'myself', password => 'secret'
   server_name => 'pop3.server.com', server_port => '120');

=error Illegal folder URL '$url'.
The folder name was specified as URL, but not according to the syntax.
See M<decodeFolderURL()> for an description of the syntax.

=error No foldername specified to open.
C<open()> needs a folder name as first argument (before the list of options),
or with the C<folder> option within the list.  If no name was found, the
MAIL environment variable is checked.  When even that does not result in
a usable folder, then this error is produced.  The error may be caused by
an accidental odd-length option list.

=warning Will never create a folder $name without having write access.
You have set M<open(create)>, but only want to read the folder.  Create is
only useful for folders which have write or append access modes
(see M<Mail::Box::new(access)>).

=warning Folder type $type is unknown, using autodetect.
The specified folder type (see M<open(type)>, possibly derived from
the folder name when specified as url) is not known to the manager.
This may mean that you forgot to require the M<Mail::Box> extension
which implements this folder type, but probably it is a typo.  Usually,
the manager is able to figure-out which type to use by itself.

=warning Folder does not exist, failed opening $type folder $name.
The folder does not exist and creating is not permitted (see
M<open(create)>) or did not succeed.  When you do not have sufficient
access rights to the folder (for instance wrong password for POP3),
this warning will be produced as well.

The manager tried to open a folder of the specified type.  It may help
to explicitly state the type of your folder with the C<type> option.
There will probably be another warning or error message which is related
to this report and provides more details about its cause.  You may also
have a look at M<new(autodetect)> and M<new(folder_types)>.

=error Folder $name is already open.
You cannot ask the manager for a folder which is already open. In some
older releases (before MailBox 2.049), this was permitted, but then
behaviour changed, because many nasty side-effects are to be expected.
For instance, an M<Mail::Box::update()> on one folder handle would
influence the second, probably unexpectedly.

=cut

sub open(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;
    $args{authentication} ||= 'AUTO';

    $name    = defined $args{folder} ? $args{folder} : ($ENV{MAIL} || '')
        unless defined $name;

    if($name =~ m/^(\w+)\:/ && grep { $_ eq $1 } $self->folderTypes)
    {   # Complicated folder URL
        my %decoded = $self->decodeFolderURL($name);
        if(keys %decoded)
        {   # accept decoded info
            @args{keys %decoded} = values %decoded;
        }
        else
        {   $self->log(ERROR => "Illegal folder URL '$name'.");
            return;
        }
    }
    else
    {   # Simple folder name
        $args{folder} = $name;
    }

    my $type = $args{type};
    if(!defined $type) { ; }
    elsif($type eq 'pop3')
    {   my $un   = $args{username}    ||= $ENV{USER} || $ENV{LOGIN};
        my $srv  = $args{server_name} ||= 'localhost';
        my $port = $args{server_port} ||= 110;
        $args{folder} = $name = "pop3://$un\@$srv:$port";
    }
    elsif($type eq 'pop3s')
    {   my $un   = $args{username}    ||= $ENV{USER} || $ENV{LOGIN};
        my $srv  = $args{server_name} ||= 'localhost';
        my $port = $args{server_port} ||= 995;
        $args{folder} = $name = "pop3s://$un\@$srv:$port";
    }
    elsif($type eq 'imap4')
    {   my $un   = $args{username}    ||= $ENV{USER} || $ENV{LOGIN};
        my $srv  = $args{server_name} ||= 'localhost';
        my $port = $args{server_port} ||= 143;
        $args{folder} = $name = "imap4://$un\@$srv:$port";
    }

    unless(defined $name && length $name)
    {   $self->log(ERROR => "No foldername specified to open.");
        return undef;
    }
        
    $args{folderdir} ||= $self->{MBM_folderdirs}->[0]
        if $self->{MBM_folderdirs};

    $args{access} ||= 'r';

    if($args{create} && $args{access} !~ m/w|a/)
    {   $self->log(WARNING
           => "Will never create a folder $name without having write access.");
        undef $args{create};
    }

    # Do not open twice.
    if(my $folder = $self->isOpenFolder($name))
    {   $self->log(ERROR => "Folder $name is already open.");
        return undef;
    }

    #
    # Which folder type do we need?
    #

    my ($folder_type, $class, @defaults);
    if($type)
    {   # User-specified foldertype prevails.
        foreach (@{$self->{MBM_folder_types}})
        {   (my $abbrev, $class, @defaults) = @$_;

            if($type eq $abbrev || $type eq $class)
            {   $folder_type = $abbrev;
                last;
            }
        }

        $self->log(ERROR => "Folder type $type is unknown, using autodetect.")
            unless $folder_type;
    }

    unless($folder_type)
    {   # Try to autodetect foldertype.
        foreach (@{$self->{MBM_folder_types}})
        {   next unless $_;
            (my $abbrev, $class, @defaults) = @$_;
            next if $require_failed{$class};

            eval "require $class";
            if($@)
            {   $require_failed{$class}++;
                next;
            }

            if($class->foundIn($name, @defaults, %args))
            {   $folder_type = $abbrev;
                last;
            }
        }
     }

    unless($folder_type)
    {   # Use specified default
        if(my $type = $self->{MBM_default_type})
        {   foreach (@{$self->{MBM_folder_types}})
            {   (my $abbrev, $class, @defaults) = @$_;
                if($type eq $abbrev || $type eq $class)
                {   $folder_type = $abbrev;
                    last;
                }
            }
        }
    }

    unless($folder_type)
    {   # use first type (last defined)
        ($folder_type, $class, @defaults) = @{$self->{MBM_folder_types}[0]};
    }
    
    #
    # Try to open the folder
    #

    return if $require_failed{$class};
    eval "require $class";
    if($@)
    {   $self->log(ERROR => "Failed for folder default $class: $@");
        $require_failed{$class}++;
        return ();
    }

    push @defaults, manager => $self;
    my $folder = $class->new(@defaults, %args);
    unless(defined $folder)
    {   $self->log(WARNING =>
           "Folder does not exist, failed opening $folder_type folder $name.")
           unless $args{access} eq 'd';
        return;
    }

    $self->log(PROGRESS => "Opened folder $name ($folder_type).");
    push @{$self->{MBM_folders}}, $folder;
    $folder;
}

=method openFolders
Returns a list of all open folders.
=cut

sub openFolders() { @{shift->{MBM_folders}} }

=method isOpenFolder $folder
Returns true if the $folder is currently open.

=example
 print "Yes\n" if $mgr->isOpenFolder('Inbox');
=cut

sub isOpenFolder($)
{   my ($self, $name) = @_;
    first {$name eq $_->name} $self->openFolders;
}

#-------------------------------------------

=method close $folder, %options

C<close> removes the specified folder from the list of open folders.
Indirectly it will update the files on disk if needed (depends on
the M<Mail::Box::new(save_on_exit)> flag for each folder). %options are
passed to M<Mail::Box::close()> of the folder.

The folder's messages will also be withdrawn from the known message threads.
You may also close the folder directly. The manager will be informed
about this event and take appropriate actions.

=option  close_by_self BOOLEAN
=default close_by_self <false>
Used internally to avoid confusion about how the close was started.  Do
not change this.

=examples

 my $inbox = $mgr->open('inbox');
 $mgr->close($inbox);
 $inbox->close;        # alternative

=cut

sub close($@)
{   my ($self, $folder, %options) = @_;
    return unless $folder;

    my $name      = $folder->name;
    my @remaining = grep {$name ne $_->name} @{$self->{MBM_folders}};

    # folder opening failed:
    return if @{$self->{MBM_folders}} == @remaining;

    $self->{MBM_folders} = [ @remaining ];
    $_->removeFolder($folder) foreach @{$self->{MBM_threads}};

    $folder->close(close_by_manager => 1, %options)
       unless $options{close_by_self};

    $self;
}

#-------------------------------------------

=method closeAllFolders, %options

C<closeAllFolders> calls close() for each folder managed by
this object.  It is called just before the program stops (before global
cleanup).

=cut

sub closeAllFolders(@)
{   my ($self, @options) = @_;
    $_->close(@options) foreach $self->openFolders;
    $self;
}

END {map {defined $_ && $_->closeAllFolders} @managers}

#-------------------------------------------

=section Manage existing folders

=method delete $foldername, %options

Remove the named folder.  The %options are the same as those for M<open()>.

The deletion of a folder can take some time.  Dependent on the type of
folder, the folder must be read first.  For some folder-types this will
be fast.

=option  recursive BOOLEAN
=default recursive <folder's default>
Some folder can only be recursively deleted, other have more flexibility.
=cut

sub delete($@)
{   my ($self, $name, %args) = @_;
    my $recurse = delete $args{recursive};

    my $folder = $self->open(folder => $name, access => 'd', %args)
        or return $self;  # still successful

    $folder->delete(recursive => $recurse);
}

#-------------------------------------------

=section Move messages to folders

=method appendMessage [$folder|$foldername], $messages, %options

Append one or more messages to a folder (therefore, an C<appendMessages()>
is defined as well). You may specify a $foldername or an opened folder
as the first argument. When the name is that of an open folder, it is
treated as if the folder-object was specified, and not directly access
the folder-files.  You may also specify the foldername as part of the
options list.

If a message is added to an already opened folder, it is only added to
the structure internally in the program.  The data will not be written to
disk until a write of that folder takes place.  When the name of an
unopened folder is given, the folder is opened, the messages stored on
disk, and then the folder is closed.

A message must be an instance of a M<Mail::Message>.  The actual message
type does not have to match the folder type--the folder will try to
resolve the differences with minimal loss of information.  The coerced
messages (how the were actually written) are returned as list.

The %options is a list of key/values, which are added to (overriding)
the default options for the detected folder type.

=examples

 $mgr->appendMessage('=send', $message, folderdir => '/');
 $mgr->appendMessage($received, $inbox->messages);

 my @appended = $mgr->appendMessages($inbox->messages,
    folder => 'Drafts');
 $_->label(seen => 1) foreach @appended;

=error Folder $name is not a Mail::Box; cannot add a message.

The folder where the message should be appended to is an object which is
not a folder type which extends M<Mail::Box>.  Probably, it is not a folder
at all.

=warning Use moveMessage() or copyMessage() to move between open folders.

The message is already part of a folder, and now it should be appended
to a different folder.  You need to decide between copy or move, which
both will clone the message (not the body, because they are immutable).

=cut

sub appendMessage(@)
{   my $self     = shift;
    my @appended = $self->appendMessages(@_);
    wantarray ? @appended : $appended[0];
}

sub appendMessages(@)
{   my $self = shift;
    my $folder;
    $folder  = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    push @messages, shift while @_ && ref $_[0];

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder) || $folder
        unless ref $folder;

    if(ref $folder)
    {   # An open file.
        unless($folder->isa('Mail::Box'))
        {   $self->log(ERROR =>
                "Folder $folder is not a Mail::Box; cannot add a message.\n");
            return ();
        }

        foreach (@messages)
        {   next unless $_->isa('Mail::Box::Message') && $_->folder;
            $self->log(WARNING =>
               "Use moveMessage() or copyMessage() to move between open folders.");
        }

        return $folder->addMessages(@messages);
    }

    # Not an open file.
    # Try to autodetect the folder-type and then add the message.

    my ($name, $class, @gen_options, $found);

    foreach (@{$self->{MBM_folder_types}})
    {   ($name, $class, @gen_options) = @$_;
        next if $require_failed{$class};
        eval "require $class";
        if($@)
        {   $require_failed{$class}++;
            next;
        }

        if($class->foundIn($folder, @gen_options, access => 'a'))
        {   $found++;
            last;
        }
    }
 
    # The folder was not found at all, so we take the default folder-type.
    my $type = $self->{MBM_default_type};
    if(!$found && $type)
    {   foreach (@{$self->{MBM_folder_types}})
        {   ($name, $class, @gen_options) = @$_;
            if($type eq $name || $type eq $class)
            {   $found++;
                last;
            }
        }
    }

    # Even the default foldertype was not found (or nor defined).
    ($name, $class, @gen_options) = @{$self->{MBM_folder_types}[0]}
        unless $found;

    $class->appendMessages
      ( type     => $name
      , messages => \@messages
      , @gen_options
      , %options
      , folder   => $folder
      );
}

#-------------------------------------------

=method copyMessage [$folder|$foldername], $messages, %options

Copy a message from one folder into another folder.  If the destination
folder is already opened, M<Mail::Box::copyTo()> is used.  Otherwise,
M<Mail::Box::appendMessages()> is called.

You need to specify a folder's name or folder object as the first
argument, or in the options list.  The options are the same as those
which can be specified when opening a folder.

=option  share BOOLEAN
=default share <false>
Try to share the physical storage of the messages.  The folder types
may be different, but it all depends on the actual folder where the
message is copied to.  Silently ignored when not possible to share.

=examples

 my $drafts = $mgr->open(folder => 'Drafts');
 my $outbox = $mgr->open(folder => 'Outbox');
 $mgr->copyMessage($outbox, $drafts->message(0));

 my @messages = $drafts->message(1,2);
 $mgr->copyMessage('=Trash', @messages,
    folderdir => '/tmp', create => 1);

 $mgr->copyMessage($drafts->message(1),
    folder => '=Drafts' folderdir => '/tmp',
    create => 1);

=error Use appendMessage() to add messages which are not in a folder.

You do not need to copy this message into the folder, because you do
not share the message between folders.

=cut

sub copyMessage(@)
{   my $self   = shift;
    my $folder;
    $folder    = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    while(@_ && ref $_[0])
    {   my $message = shift;
        $self->log(ERROR =>
            "Use appendMessage() to add messages which are not in a folder.")
                unless $message->isa('Mail::Box::Message');
        push @messages, $message;
    }

    my %args = @_;
    $folder ||= $args{folder};
    my $share   = exists $args{share} ? $args{share} : $args{_delete};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder) || $folder
        unless ref $folder;

    unless(ref $folder)
    {   my @c = $self->appendMessages(@messages, %args, folder => $folder);
        if($args{_delete})
        {   $_->label(deleted => 1) for @messages;
        }
        return @c;
    }

    my @coerced;
    foreach my $msg (@messages)
    {   if($msg->folder eq $folder)  # ignore move to same folder
        {   push @coerced, $msg;
            next;
        }
        push @coerced, $msg->copyTo($folder, share => $args{share});
        $msg->label(deleted => 1) if $args{_delete};
    }
    @coerced;
}

#-------------------------------------------

=method moveMessage [$folder|$foldername], $messages, %options

Move a message from one folder to another.

BE WARNED that removals from a folder only take place when the folder
is closed, so the message is only flagged to be deleted in the opened
source folder.

BE WARNED that message labels may get lost when a message is moved from
one folder type to an other.  An attempt is made to translate labels,
but there are many differences in interpretation by applications.

 $mgr->moveMessage($received, $inbox->message(1))

is equivalent to

 $mgr->copyMessage($received, $inbox->message(1), share => 1);
 $inbox->message(1)->delete;

=option  share BOOLEAN
=default share <true>

=cut

sub moveMessage(@)
{   my $self = shift;
    $self->copyMessage(@_, _delete => 1);
}

#-------------------------------------------

=section Manage message threads

=method threads [$folders], %options

Create a new object which keeps track of message threads.  You can
read about the possible options in M<Mail::Box::Thread::Manager>.
As %options specify one folder or an array of $folders.
It is also permitted to specify folders before the options.

=examples

 my $t1 = $mgr->threads(folders => [ $inbox, $send ]);
 my $t2 = $mgr->threads($inbox);
 my $t3 = $mgr->threads($inbox, $send);

=cut

sub threads(@)
{   my $self    = shift;
    my @folders;
    push @folders, shift
       while @_ && ref $_[0] && $_[0]->isa('Mail::Box');
    my %args    = @_;

    my $base    = 'Mail::Box::Thread::Manager';
    my $type    = $args{threader_type} || $base;

    my $folders = delete $args{folder} || delete $args{folders};
    push @folders
     , ( !$folders               ? ()
       : ref $folders eq 'ARRAY' ? @$folders
       :                           $folders
       );

    $self->log(INTERNAL => "No folders specified.")
       unless @folders;

    my $threads;
    if(ref $type)
    {   # Already prepared object.
        $self->log(INTERNAL => "You need to pass a $base derived")
            unless $type->isa($base);
        $threads = $type;
    }
    else
    {   # Create an object.  The code is compiled, which safes us the
        # need to compile Mail::Box::Thread::Manager when no threads are needed.
        eval "require $type";
        $self->log(INTERNAL => "Unusable threader $type: $@") if $@;

        $self->log(INTERNAL => "You need to pass a $base derived")
            unless $type->isa($base);

        $threads = $type->new(manager => $self, %args);
    }

    $threads->includeFolder($_) foreach @folders;
    push @{$self->{MBM_threads}}, $threads;
    $threads;
}

#-------------------------------------------

=section Internals

=method toBeThreaded $folder, $messages
Signal to the manager that all thread managers which are using the
specified folder must be informed that new messages are
coming in.
=cut

sub toBeThreaded($@)
{   my $self = shift;
    $_->toBeThreaded(@_) foreach @{$self->{MBM_threads}};
}

=method toBeUnthreaded $folder, $messages
Signal to the manager that all thread managers which are using the
specified folder must be informed that new messages are
or going out.
=cut

sub toBeUnthreaded($@)
{   my $self = shift;
    $_->toBeUnthreaded(@_) foreach @{$self->{MBM_threads}};
}

=method decodeFolderURL $url
Try to decompose a folder name which is specified as $url (see open())
into separate options.  Special characters like @-sign, colon, and slash
used in the user or password parts must be passed $url-encoded.
=cut

sub decodeFolderURL($)
{   my ($self, $name) = @_;

    return unless
       my ($type, $username, $password, $hostname, $port, $path)
          = $name =~ m!^(\w+)\:             # protocol
                       (?://
                          (?:([^:@/]*)      # username
                            (?:\:([^@/]*))? # password
                           \@)?
                           ([\w.-]+)?       # hostname
                           (?:\:(\d+))?     # port number
                        )?
                        (.*)                # foldername
                      !x;

    $username ||= $ENV{USER} || $ENV{LOGNAME};
    $password ||= '';

    for($username, $password)
    {   s/\+/ /g;
        s/\%([A-Fa-f0-9]{2})/chr hex $1/ge;
    }

    $hostname ||= 'localhost';

    $path     ||= '=';

    ( type        => $type,     folder      => $path
    , username    => $username, password    => $password
    , server_name => $hostname, server_port => $port
    );
}

#-------------------------------------------

=section Error handling

=chapter DETAILS
On many places in the documentation you can read that it is useful to
have a manager object.  There are two of them: the M<Mail::Box::Manager>,
which maintains a set of open folders, and an extension of it: the
M<Mail::Box::Manage::User>.

=section Managing open folders
It is useful to start your program by creating a folder manager object,
an M<Mail::Box::Manager>.  The object takes a few burdons from your neck:

=over 4
=item * autodetect the type of folder which is used.
This means that your application can be fully folder type independent.

=item * autoload the required modules
There are so many modules involved in MailBox, that it is useful to
have some lazy autoloading of code.  The manager knows which modules
belong to which type of folder.

=item * avoid double openings
Your programming mistakes may cause the same folder to be opened twice.
The result of that could be very destructive.  Therefore, the manager
keeps track on all open folders and avoids the same folder to be opened
for the second time.

=item * close folders at clean-up
When the program is ending, the manager will cleanly close all folders
which are still open.  This is required, because the autodestruct
sequence of Perl works in an unpredicatable order.

=item * message thread detection
MailBox can discover message threads which span multiple folders. Any set
of open folders may be grouped in a tree of replies on replies on replies.
When a folder is closed, it will automatically be removed from the threads,
and a new folder can dynamically be added to the structure.
=back

The manager is really simplifying things, and should therefore be the
base of all programs. However, it is possible to write useful programs
without it.

=section Managing a user

One step further is the M<Mail::Box::Manage::User> object (since MailBox
v2.057), which not only keeps track on open folders, but also collects
information about not-open folders.

The user class is, as the name says, targeted on managing one single user.
Where the M<Mail::Box::Manager> will open any set of folder files, probably
from multiple users, the user class want one root folder directory.

In many aspects, the user manager simplifies the task for user-based servers
and other user-centric applications by setting smart defaults.

=cut

1;
