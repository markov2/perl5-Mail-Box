use strict;
use warnings;

package Mail::Box::Manager;
use base 'Mail::Reporter';

our $VERSION = 2.018;
use Mail::Box;

use Carp;
use List::Util   'first';
use Scalar::Util 'weaken';

#-------------------------------------------

=head1 NAME

Mail::Box::Manager - manage a set of folders

=head1 CLASS HIERARCHY

 Mail::Box::Manager
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr     = new Mail::Box::Manager;
 $mgr->registerType(mbox => 'Mail::Box::Mbox');

 # Create folder objects.
 my $folder  = $mgr->open(folder => $ENV{MAIL});
 my $message = $folder->message(0);
 my ($message1, $message2) = ($folder->message(1), $folder->message(2));
 $mgr->copyMessage('Draft', $message);
 $mgr->moveMessage('Outbox', $message1, $message2, create => 1 );
 $mgr->close($folder);

 # Create thread-detectors (see Mail::Box::Thread::Manager)
 my $t       = $mgr->threads($inbox, $outbox);

 my $threads = $mgr->threads(folder => $folder);
 foreach my $thread ($threads->all)
 {   $thread->print;
 }

=head1 DESCRIPTION

The manager keeps track on a set of open folders and a set of message-thread
supporting objects.  You are not obliged to use this object (you can
directly create a C<Mail::Box::Mbox> if you prefer), but you will create
more portable and safer code if you do use it.

Read C<Mail::Box-Overview> first.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR).

The general methods for C<Mail::Box::Manager> objects:

      appendMessages [FOLDER|FOLD...       new ARGS
      close FOLDER, OPTIONS                open [FOLDERNAME], OPTIONS
      closeAllFolders, OPTIONS             openFolders
      copyMessage [FOLDER|FOLDERN...       registerType TYPE =E<gt> CL...
      decodeFolderURL URL               MR report [LEVEL]
      delete FOLDERNAME [,OPTIONS]      MR reportAll [LEVEL]
   MR errors                               threads [FOLDERS], OPTIONS
      folderTypes                          toBeThreaded FOLDER, MESSAGES
      isOpenFolder FOLDER                  toBeUnthreaded FOLDER, MESS...
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      moveMessage [FOLDER|FOLDERN...    MR warnings

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

(class method) Create a new folder manager.  This constructor may specify
the following options:

 OPTION              DESCRIBED IN         DEFAULT
 default_folder_type Mail::Box::Manager   'mbox'
 folder_types        Mail::Box::Manager   <mbox and mh>
 folderdir           Mail::Box::Manager   [ '.' ]
 folderdirs          Mail::Box::Manager   <synon for folderdir>
 log                 Mail::Reporter       'WARNINGS'
 trace               Mail::Reporter       'WARNINGS'

=over 4

=item * folder_types =E<gt> [ NAME =E<gt> CLASS [,OPTIONS] ]

=item * folder_types =E<gt> [ [ NAME =E<gt> CLASS [,OPTIONS] ], [...] ]

Add one or more folder_types to the list of known types.  The order is
important: when you open a file without specifying its type, the
manager will start trying the last added list of types, in order.

You may specify folder-specific defaults as OPTIONS.  They override
the settings of the manager.

=item * default_folder_type =E<gt> NAME|CLASS

Specifies the default folder type for newly created folders.  If this
option is not specified, the most recently registered type is used (see
C<registerType> and the C<folder_types> option.

=item * folderdir =E<gt> DIRECTORY

=item * folderdirs =E<gt> [ DIRECTORY, ... ]

The default directory, or directories, where folders are
located.  C<Mail::Box::Manager> can autodetect the existing folder-types.
There may be different kinds of folders opened at the same time, and
messages can be moved between those types, although that may result in
a loss of information depending on the folder types.

=back

=cut

my @basic_folder_types =
  ( [ mbox    => 'Mail::Box::Mbox'    ]
  , [ mh      => 'Mail::Box::MH'      ]
  , [ maildir => 'Mail::Box::Maildir' ]
  , [ pop     => 'Mail::Box::POP3'    ]
  , [ pop3    => 'Mail::Box::POP3'    ]
  );

my @managers;  # usually only one, but there may be more around :(

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    # Register all folder-types.  There may be some added later.

    my @types;
    if(exists $args->{folder_types})
    {   @types = ref $args->{folder_types}[0]
               ? @{$args->{folder_types}}
               : $args->{folder_types};
    }

    $self->{MBM_folder_types} = [];
    $self->registerType(@$_) foreach @types, reverse @basic_folder_types;

    $self->{MBM_default_type} = $args->{default_folder_type};

    # Invertory on existing folder-directories.

    $self->{MBM_folderdirs} = [ '.' ];
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

    $self->{MBM_folders} = [];
    $self->{MBM_threads} = [];

    push @managers, $self;
    weaken $managers[-1];

    $self;
}

#-------------------------------------------

=item registerType TYPE =E<gt> CLASS [,OPTIONS]

With C<registerType> you can register one TYPE of folders.  The CLASS
is compiled automatically, so you do not need to C<use> them in your own
modules.  The TYPE is just an arbitrary name.

The added types are prepended to the list of known types, so they are
checked first when a folder is opened in autodetect mode.

Example:

 $manager->registerType(mbox => 'Mail::Box::Mbox',
     save_on_exit => 0, folderdir => '/tmp');

=cut

sub registerType($$@)
{   my ($self, $name, $class, @options) = @_;
    unshift @{$self->{MBM_folder_types}}, [$name, $class, @options];
    $self;
}

#-------------------------------------------

=item folderTypes

The C<folderTypes> returns the list of currently defined folder types.

Example:

   print join("\n", $manager->folderTypes), "\n";

=cut

sub folderTypes()
{   my $self = shift;
    my %uniq;
    $uniq{$_->[0]}++ foreach @{$self->{MBM_folder_types}};
    sort keys %uniq;
}

#-------------------------------------------

=back

=head1 METHODS to handle folders

=over 4

=item open [FOLDERNAME], OPTIONS

Open a folder which name is specified as first parameter or with
the option flag C<folder>.  The folder type is autodetected unless
the C<type> is specified.

C<open> carries options for the manager which are described here, but
may also have additional options for the folder type.  For a
description of the folder options, see the options to the constructor
(the C<new> method) for each type of mail-box, as well as the general
folder options for the constructor of the C<Mail::Box> base class.

The options which are most common to C<open()>:

=over 4

=item * create =E<gt> BOOL

Create the folder if it does not exist. By default, this is not done.
The C<type> option specifies which type of folder is created.

=item * folder =E<gt> NAME|URL

Which folder to open, specified by NAME or special URL.  The default
folder is taken from $ENV{MAIL}.

The URL format is composed as

 type://username:password@hostname:port/foldername

Like real urls, all fields are optional and have smart defaults, as long
as the string starts with a known folder type.  Far
from all folder types support all these options, but at least they are
all split-out.

When you specify anything which does not match the URL format, it is
passed directly to the C<new> method of the folder which is opened.

=item * folderdir =E<gt> DIRECTORY

The directory where the folders are usually stored.

=item * type =E<gt> FOLDERTYPENAME|FOLDERTYPE

Specify the type of the folder.  If you do not specify this option while
opening a folder for reading, the manager checks all registered folder
types in order for the ability to open the folder. If you open a new
folder for writing, then the default will be the most recently registered
type. (If you add more than one type at once, the first of the list is
used.)

=back

Examples:

 my $jack  = $manager->open(folder => '=jack', type => 'mbox');
 my $rcvd  = $manager->open(type => 'Mail::Box::Mbox', access => 'rw');

 my $inbox = $manager->open('Inbox')
    or die "Cannot open Inbox.\n";

 my $send  = $manager->open('pop3://myself:secret@pop3.server.com:120/x');
 my $send  = $manager->open(folder => '/x', type => 'pop3'
   , username    => 'myself', password => 'secret'
   , server_name => 'pop3.server.com', server_port => '120');

=cut

sub open(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;

    $name    = defined $args{folder} ? $args{folder} : $ENV{MAIL}
        unless defined $name;

    if($name =~ m/^(\w+)\:/ && grep { $_ eq $1 } $self->foldertypes)
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

    unless(defined $name && length $name)
    {   $self->log(ERROR => "No foldername specified to open.\n");
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
    {   $self->log(NOTICE => "Folder $name is already open.\n");
        return $folder;
    }

    #
    # Which folder type do we need?
    #

    my ($folder_type, $class, @defaults);
    if(my $type = $args{type})
    {   # User-specified foldertype prevails.
        foreach (@{$self->{MBM_folder_types}})
        {   (my $abbrev, $class, @defaults) = @$_;

            if($type eq $abbrev || $type eq $class)
            {   $folder_type = $abbrev;
                last;
            }
        }

        $self->log(ERROR=>"Folder type $type is unknown, using autodetect")
            unless $folder_type;
    }

    unless($folder_type)
    {   # Try to autodetect foldertype.
        foreach (@{$self->{MBM_folder_types}})
        {   (my $abbrev, $class, @defaults) = @$_;

            eval "require $class";
            next if $@;

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

    eval "require $class";
    croak if $@;

    push @defaults, manager => $self;
    my $folder = $class->new(@defaults, %args);

    unless(defined $folder)
    {   # Create the folder if it does not exist yet.
        $self->log(WARNING
                => "Folder $name does not exist ($folder_type)."), return
             unless $args{create};

        $self->log(WARNING
                => "Unable to create folder $name ($folder_type)."), return
            unless $class->create($name, @defaults, %args);

        $self->log(PROGRESS => "Created folder $name ($folder_type).");
        $folder = $class->new(@defaults, %args);
    }

    $self->log(PROGRESS => "Opened folder $name ($folder_type).");
    push @{$self->{MBM_folders}}, $folder;
    $folder;
}

#-------------------------------------------

=item openFolders

Returns a list of all open folders.

=cut

sub openFolders() { @{shift->{MBM_folders}} }

#-------------------------------------------

=item isOpenFolder FOLDER

Returns true if the FOLDER is currently open.

Example:

    print "Yes\n" if $mgr->isOpenFolder('Inbox');

=cut

sub isOpenFolder($)
{   my ($self, $name) = @_;
    first {$name eq $_->name} $self->openFolders;
}

#-------------------------------------------

=item close FOLDER, OPTIONS

=item closeAllFolders, OPTIONS

C<close> removes the specified folder from the list of open folders.
Indirectly it will update the files on disk if needed (depends on
the C<save_on_exit> flag for each folder). OPTIONS are passed to
the C<close> method of each folder.

The folder's messages will also be withdrawn from the known message threads.
You may also close the folder directly. The manager will be informed
about this event and take appropriate actions.

Examples:

 my $inbox = $mgr->open('inbox');
 $mgr->close($inbox);
 $inbox->close;        # alternative

C<closeAllFolders> calls C<close> for each folder managed by
this object.  It is called just before the program stops (before global
cleanup).

=cut

sub close($@)
{   my ($self, $folder, @options) = @_;
    return unless $folder;

    my $name      = $folder->name;
    my @remaining = grep {$name ne $_->name} @{$self->{MBM_folders}};

    # folder opening failed:
    return if @{$self->{MBM_folders}} == @remaining;

    $self->{MBM_folders} = [ @remaining ];
    $_->removeFolder($folder) foreach @{$self->{MBM_threads}};

    $folder->close(close_by_manager => 1, @options);
    $self;
}

sub closeAllFolders(@)
{   my ($self, @options) = @_;
    $_->close(@options) foreach $self->openFolders;
    $self;
}

END {map {defined $_ && $_->closeAllFolders} @managers}

#-------------------------------------------

=item appendMessages [FOLDER|FOLDERNAME,] MESSAGES, OPTIONS

Append one or more messages to a folder. You may specify a FOLDERNAME or
an opened folder as the first argument. When the name is that of an
open folder, it is treated as if the folder-object was specified, and
not directly access the folder-files.  You may also specify the
foldername as part of the options list.

If a message is added to an already opened folder, it is only added to
the structure internally in the program.  The data will not be written to
disk until a write of that folder takes place.  When the name of an
unopened folder is given, the folder is opened, the messages stored on
disk, and then the folder is closed.

A message must be an instance of an C<Mail::Message>.  The actual message
type does not have to match the folder type--the folder will try to
resolve the differences with minimal loss of information.  The coerced
messages (how the were actually written) are returned as list.

The OPTIONS is a list of key/values, which are added to (overriding)
the default options for the detected folder type.

Examples:

   $mgr->appendMessages('=send', $message, folderdir => '/');
   $mgr->appendMessages('=received', $inbox->messages);

   my @appended = $mgr->appendMessages($inbox->messages,
        folder => 'Drafts');
   $_->label(seen => 1) foreach @appended;

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
          "Use moveMessage() or copyMessage() to move between opened folders.");
        }

        return $folder->addMessages(@messages);
    }

    # Not an open file.
    # Try to autodetect the folder-type and then add the message.

    my ($name, $class, @gen_options, $found);

    foreach (@{$self->{MBM_folder_types}})
    {   ($name, $class, @gen_options) = @$_;
        eval "require $class";
        next if $@;

        if($class->foundIn($folder, @gen_options))
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

    # Even the default foldertype was not found.
    ($name, $class, @gen_options) = @{$self->{MBM_folder_types}[1]}
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

=item copyMessage [FOLDER|FOLDERNAME,] MESSAGES, OPTIONS

Copy a message from one folder into another folder.  If the destination
folder is already opened, the copied message is stored in memory and
written to disk when a write of the folder is later performed. Otherwise,
the destination folder will be opened, the message written, and then the
folder closed.

You need to specify a folder's name or folder object as the first
argument, or in the options list.  The options are the same as those
which can be specified when opening a folder.

Examples:

 my $drafts = $mgr->open(folder => 'Drafts');
 my $outbox = $mgr->open(folder => 'Outbox');
 $mgr->copyMessage($outbox, $drafts->message(0));

 $mgr->copyMessage('Trash', $drafts->message(1), $drafts->message(2),
    folderdir => '/tmp', create => 1);

 $mgr->copyMessage($drafts->message(1), folder => 'Drafts'
    folderdir => '/tmp', create => 1);

=cut

sub copyMessage(@)
{   my $self   = shift;
    my $folder;
    $folder    = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    while(@_ && ref $_[0])
    {   my $message = shift;
        croak "Use appendMessage to add messages which are not in a folder."
           unless $message->isa('Mail::Box::Message');
        push @messages, $message;
    }

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder) || $folder
        unless ref $folder;

    my @coerced
     = ref $folder
     ? map {$_->copyTo($folder)} @messages
     :  $self->appendMessages(@messages, %options, folder => $folder);

    # hidden option, do not use it: it's designed to optimize moveMessage
    if($options{_delete})
    {   $_->delete foreach @messages;
    }

    @coerced;
}

#-------------------------------------------

=item moveMessage [FOLDER|FOLDERNAME,] MESSAGES, OPTIONS

Move a message from one folder to another.  Be warned that removals from
a folder only take place when the folder is closed, so the message is only
flagged to be deleted in the opened source folder.

   $mgr->moveMessage($received, $inbox->message(1))

is equivalent to

   $mgr->copyMessage($received, $inbox->message(1));
   $inbox->message(1)->delete;

=cut

sub moveMessage(@)
{   my $self = shift;
    $self->copyMessage(@_, _delete => 1);
}

#-------------------------------------------

=item delete FOLDERNAME [,OPTIONS]

Remove the named folder, including all its sub-folders.  The OPTIONS
are the same as those for C<open()>.

The deletion of a folder can take some time.  Dependent on the type of
folder, the folder must be read first.  For some folder-types this will
be fast.

=cut

sub delete($@)
{   my ($self, $name, @options) = @_;
    my $folder = $self->open(folder => $name, @options) or return;
    $folder->delete;
}

#-------------------------------------------

=back

=head1 METHODS to handle thread-objects

=over 4

=cut

#-------------------------------------------

=item threads [FOLDERS], OPTIONS

Create a new object which keeps track of message threads.  You can read
about the possible options in the C<Mail::Box::Thread::Manager> documentation.
As OPTIONS specify one C<folder> or an array of C<folders>.  It is also
permitted to specify folders before the options.

Example:

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

    croak "No folders specified.\n" unless @folders;

    my $threads;
    if(ref $type)
    {   # Already prepared object.
        confess "You need to pass a $base derived"
            unless $type->isa($base);
        $threads = $type;
    }
    else
    {   # Create an object.  The code is compiled, which safes us the
        # need to compile Mail::Box::Thread::Manager when no threads are needed.
        eval "require $type";
        croak "Unusable threader $type: $@" if $@;
        croak "You need to pass a $base derived"
            unless $type->isa($base);

        $threads = $type->new(manager => $self, %args);
    }

    $threads->includeFolder($_) foreach @folders;
    push @{$self->{MBM_threads}}, $threads;
    $threads;
}

#-------------------------------------------

=item toBeThreaded FOLDER, MESSAGES

=item toBeUnthreaded FOLDER, MESSAGES

Signal to the manager that all thread managers which are using the
specified folder must be informed that new messages are
coming in (or going out).

=cut

sub toBeThreaded($@)
{   my $self = shift;
    $_->toBeThreaded(@_) foreach @{$self->{MBM_threads}};
}

sub toBeUnthreaded($@)
{   my $self = shift;
    $_->toBeUnthreaded(@_) foreach @{$self->{MBM_threads}};
}

#-------------------------------------------

=item decodeFolderURL URL

Try to decompose a folder name which is specified as URL (see the
C<open> method) into separate options.

=cut

sub decodeFolderURL($)
{   my ($self, $name) = @_;

    return unless
       my ($type, $username, $password, $hostname, $port, $path)
          = $name =~ m!^(\w+)\:             # protocol
                       (?://
                          (?:([^:@./]*)     # username
                            (?:\:([^@/]*))? # password
                           \@)?
                           ([\w.-]+)?       # hostname
                           (?:\:(\d+))?     # portnumber
                        )?
                        (.*)                # foldername
                      !x;

    $username ||= $ENV{USER} || $ENV{LOGNAME};
    $password ||= '';
    $hostname ||= 'localhost';
    $path     ||= '=';

    { type        => $type,     folder      => $path
    , username    => $username, password    => $password
    , server_name => $hostname, server_port => $port
    };
}


#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
