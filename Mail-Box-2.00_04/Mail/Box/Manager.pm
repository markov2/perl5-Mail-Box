
package Mail::Box::Manager;

use base 'Mail::Reporter';
use Mail::Box;

use strict;
use Carp;

=head1 NAME

Mail::Box::Manager - Manage a set of folders

=head1 SYNOPSIS

   use Mail::Box::Manager;
   my $mgr    = new Mail::Box::Manager;
   $mgr->registerType(mbox => 'Mail::Box::Mbox');

   # Create folder objects.
   my $folder = $mgr->open(folder => $ENV{MAIL});
   my $message = $folder->message(0);
   my ($message1, $message2) = ($folder->message(1), $folder->message(2));
   $mgr->copyMessage('Draft', $message);
   $mgr->moveMessage('Outbox', $message1, $message2, create => 1 );
   $mgr->close($folder);

   # Create thread-detectors (see Mail::Box::Threads)
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

=head1 METHODS for manager configuration

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
  ( [ mbox  => 'Mail::Box::Mbox' ]
  , [ mh    => 'Mail::Box::MH'  ]
  );

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

    eval "require $class";
    if($@)
    {   warn "Cannot find folder type $name: $@\n";
        return 0;
    }

    unless($class->isa('Mail::Box'))
    {   $self->log(ERROR => "Cannot use type $class for folders, "
                          . "because it is not derived from Mail::Box.");
        return undef;
    }

    unshift @{$self->{MBM_folder_types}}, [$name, $class, @options];
    return $self;
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

=item open ARGS

Open a folder.  The folder type is autodetected unless the C<type> is
specified.  C<open> carries options for the manager which are described
here, but may also have additional options for the folder type.  For a
description of the folder options, see the options to the constructor
(the C<new> method) for each type of mail-box, as well as the general
folder options for the constructor of the C<Mail::Box> base class.

The options which are most common to C<open()>:

=over 4

=item * folder =E<gt> FOLDERNAME

Which folder to open.  The default folder is $ENV{MAIL}.

=item * folderdir =E<gt> DIRECTORY

The directory where the folders are usually stored.

=item * type =E<gt> FOLDERTYPENAME|FOLDERTYPE

Specify the type of the folder.  If you do not specify this option while
opening a folder for reading, the manager checks all registered folder
types in order for the ability to open the folder. If you open a new
folder for writing, then the default will be the most recently registered
type. (If you add more than one type at once, the first of the list is
used.)

Examples:

   $manager->open(folder => '=jack', type => 'mbox');
   $manager->open(type => 'Mail::Box::Mbox', access => 'rw');

=item * create =E<gt> BOOL

Create the folder if it does not exist. By default, this is not done.
The C<type> option specifies which type of folder is created.

=back

=cut

sub open(@)
{   my ($self, %args) = @_;
    my $name          = $args{folder} ||= $ENV{MAIL};

    unless(defined $name && length $name)
    {   warn "No foldername specified.\n";
        return undef;
    }
        
    $args{folderdir} ||= $self->{MBM_folderdirs}->[0]
        if $self->{MBM_folderdirs};

    # Do not open twice.
    my ($folder) = $self->isOpenFolder($name);
    if(defined $folder)
    {   warn "Folder $name is already open.\n";
        return;
    }

    # User-specified foldertype prevails.
    if(defined $args{type})
    {   foreach (@{$self->{MBM_folder_types}})
        {   my ($type, $class, @options) = @$_;
            push @options, manager => $self;
            next unless $args{type} eq $type || $args{type} eq $class;

            my $folder = $class->new(@options, %args);
            $folder = $class->create($name, @options, %args)
                if !$folder && $args{create};

            push @{$self->{MBM_folders}}, $folder if $folder;
            return $folder;
        }
        warn "I do not know foldertype $args{type}: autodecting.";
    }

    # Try to autodetect foldertype.
    my @find_options;
    push @find_options, folderdir => $args{folderdir}
        if $args{folderdir};

    foreach (@{$self->{MBM_folder_types}})
    {   my ($type, $class, @options) = @$_;
        push @options, manager => $self;
        next unless $class->foundIn($name, @find_options);

        my $folder = $class->new(@options, %args);
        push @{$self->{MBM_folders}}, $folder if $folder;
        return $folder;
    }

    # Open read-only only for folders which exist.
    if(exists $args{mode} && $args{mode} ne 'rw')
    {   warn "Couldn't detect type of folder $name.\n";
        return;
    }

    # Create a new folder.

    return unless $args{create};

    my $retry = $self->{MBM_default_type} || $self->{MBM_folder_types}[0][1];
    $retry->create($name, %args) or return;
    $self->open(%args, type => $retry);  # retry to open.
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
    (grep {$name eq $_->name} $self->openFolders)[0];
}

#-------------------------------------------

=item close FOLDER

=item closeAllFolders

C<close> removes the specified folder from the list of open folders.
Indirectly it will update the files on disk if needed (depends on
the C<save_on_exit> flag for each folder).  The folder's messages
will also be withdrawn from the known message threads.

You may also close the folder directly. The manager will be informed
about this event and take appropriate actions.

Examples:

    my $inbox = $mgr->open('inbox');
    $mgr->close($inbox);
    $inbox->close;        # alternative

C<closeAllFolders> calls C<close> for each folder managed by
this object.

=cut

sub close($)
{   my ($self, $folder) = @_;
    return unless $folder;

    my $name      = $folder->name;
    my @remaining = grep {$name ne $_->name} @{$self->{MBM_folders}};

    if(@{$self->{MBM_folders}} == @remaining)
    {   warn "The folder was not opened by this folder-manager.\n";
        return;
    }

    $self->{MBM_folders} = [ @remaining ];
    $_->removeFolder($folder) foreach @{$self->{MBM_threads}};

    $folder->close(close_by_manager => 1);
    $self;
}

sub closeAllFolders()
{   my $self = shift;
    $_->close foreach $self->openFolders;
    $self;
}

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
resolve the differences with minimal loss of information.

The OPTIONS is a list of key/values, which are added to (overriding)
the default options for the detected folder type.

Examples:

   $mgr->appendMessages('=send', $message, folderdir => '/');
   $mgr->appendMessages('=received', $inbox->messages);
   $mgr->appendMessages($inbox->messages, folder => 'Drafts');

=cut

sub appendMessage(@) {shift->appendMessages(@_)} # compatibility

sub appendMessages(@)
{   my $self = shift;
    my $folder;
    $folder  = shift if !ref $_[0] || $_[0]->isa('Mail::Box');

    my @messages;
    push @messages, shift while @_ && ref $_[0];

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder)
        if !ref $folder && $self->isOpenFolder($folder);

    if(ref $folder)
    {   # An open file.
        unless($folder->isa('Mail::Box'))
        {   warn "Folder $folder is not a Mail::Box; cannot add a message.\n";
            return;
        }

        foreach (@messages)
        {   next unless $_->isa('Mail::Box::Message') && $_->folder;
            use Carp;
            croak "Use moveMessage() or copyMessage() to move between opened folders.\n";
        }

        return $folder->addMessages(@messages);
    }

    # Not an open file.
    # Try to autodetect the folder-type and then add the message.

    my ($name, $class, @gen_options, $found);

    foreach (@{$self->{MBM_folder_types}})
    {   ($name, $class, @gen_options) = @$_;
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
    push @messages, shift while @_ && ref $_[0];

    my %options = @_;
    $folder ||= $options{folder};

    # Try to resolve filenames into opened-files.
    $folder = $self->isOpenFolder($folder)
        if !ref $folder && $self->isOpenFolder($folder);

    if(ref $folder) { $_->copyTo($folder) foreach @messages }
    else { $self->appendMessages(@messages, %options, folder => $folder) }

    # '_delete' is a hidden option to simplify the implementation of
    # moveMessages.  It should not be used by callers of copyMessage().
    if($options{_delete})
    {   $_->delete foreach @messages;
    }

    $self;
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
{   my $self   = shift;
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

=item threads OPTIONS

Create a new object which keeps track of message threads.  You can read
about the possible options in the C<Mail::Box::Threads> documentation.

Example:

    $mgr->threads(folders => [ $inbox, $send ]);

=cut

sub threads(@)
{   my ($self, %args) = @_;
    my $type    = $args{threader_type} || 'Mail::Box::Threads';
    my $base    = 'Mail::Box::Threads';


    my $folders = exists $args{folder}    ? delete $args{folder}
                :                           delete $args{folders};

    my @folders = !$folders               ? ()
                : ref $folders eq 'ARRAY' ? @$folders
                :                           $folders;

    my $threads;
    if(ref $type)
    {   # Already prepared object.
        confess "You need to pass a $base derived"
            unless $type->isa($base);
        $threads = $type;
    }
    else
    {   # Create an object.  The code is compiled, which safes us the
        # need to compile Mail::Box::Threads when no threads are needed.
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

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_04

=cut

1;