
package Mail::Box::Manager;

use strict;
use Mail::Box;
use Carp;

=head1 NAME

Mail::Box::Manager - Manage a set of folders

=head1 SYNOPSIS

   use Mail::Box::Manager;
   my $mgr    = new Mail::Box::Manager;
   $mgr->registerType(mbox => 'Mail::Box::Mbox');

   # Create folder objects.
   my $folder = $mgr->open(folder => $ENV{MAIL});
   $mgr->close($folder);
   $mgr->copyMessage('Draft', $message);
   $mgr->moveMessage('Outbox', $message1, $message2, create => 1 );

   # Create thread-detectors (see Mail::Box::Threads)
   my $threads = $mgr->threads(folder => $folder);

=head1 DESCRIPTION

This code is beta, which means that there are no serious applications
written with it yet.  Please inform the author when you have, so this
module can go to stable.  Read the STATUS file enclosed in the package for
more details.  You may also want to have a look in the example B<scripts>
which come with the module.

The Mail::Box package can be used as back-end to Mail User-Agents
(MUA's), and has special features to help those agents to get fast
access to folder-data.  These features may delay access to folders
for other kinds of applications.  Maybe Mail::Procmail has more for
you in such cases.

=head2 The folder manager

The folder manager maintains a set of folders (mail-boxes).  Those
folders may be of different types.  Most folder-types can be detected
automatically.  This manager-class is the only one you create in your
program: all other classes will come when needed.

Overview:

  Mail::Box::Manager 
        |
        | open()
        |                           
        v           contains
  Mail::Box::Mbox <-----------> Mail::Box
  (Mail::Box::MH)                ::Mbox::Message
       isa                             isa
     Mail::Box    ............. Mail::Box::Message
                                       isa
                                   MIME::Entity
                                       isa
                                  Mail::Internet

All classes are written to be extendible.  The most complicated work
is done in MIME::Entity, which is written and maintained by
Eryq (eryq@zeegee.com).

=head2 The threads manager

Most messages are replies on other messages.  It is pleasant to read mail
when you see directly how messages relate.  Certainly when the amount
of messages grow to dozins a day.

The main manager also keeps overview on the created thread-detection
objects, and informs them when the content of a folder is changed.  In
extention to other Mail-Agents, Mail::Box can show you threads which are
spread over more than one folder.

=head1 METHODS for the manager

=over 4

=cut

#-------------------------------------------

=item new ARGS

(class method) Create a new folder manager.  This constructor
may carry the following options:

=over 4

=item * folder_types =E<gt> [ NAME =E<gt> CLASS [,OPTIONS] ]

=item * folder_types =E<gt> [ [ NAME =E<gt> CLASS [,OPTIONS] ], [...] ]

Add one or more folder_types to the list of known types.  The order is
important: when you open a file without specifying its type, the
manager will start trying the last added set of types, with precedence
for the first of that list.

You may specify folder-specific defaults as OPTIONS.  They overrule
the settings of the manager.

=item * default_folder_type =E<gt> NAME|CLASS

When a new folder is created, it is of this type.  If this option is
not specified, the most recently registered type is used (see
C<registerType> and the C<folder_types>-option.

=item * folderdir =E<gt> DIRECTORY

=item * folderdirs =E<gt> [ DIRECTORY, ... ]

The default directory, respectively directories, where folders are
located.  Mail::Box::Manager can autodetect the existing folder-types.
There may be different kinds of folders opened at the same time, and
messages can be moved between those types, although that may result in
a loss of information.

=back

=cut

my @basic_folder_types =
  ( [ mbox  => 'Mail::Box::Mbox' ]
  , [ mh    => 'Mail::Box::MH'  ]
  );

sub new(@)
{   my ($class, %args) = @_;
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

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

    $self->{MBM_folderdirs} = [];
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
is compiled immediately, so you do not need to C<use> them in your own
modules.  The TYPE is just an arbitrary name.

The added types are put in front of the known types, so are checked first
when a folder is opened in autodetect mode.

Example:

   $manager->registerType(mbox => 'Mail::Box::Mbox',
       save_on_exit => 0, folderdir => '/tmp');

=cut

sub registerType($$@)
{   my ($self, $name, $class, @options) = @_;

    eval "require $class";
    if($@)
    {   warn "Cannot find foldertype $name: $@\n";
        return 0;
    }

    unshift @{$self->{MBM_folder_types}}, [$name, $class, @options];
    return 1;
}

#-------------------------------------------

=item folderTypes

The C<folderTypes> returns the list of currently defined types.

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

Open a folder.  The folder-type is autodetected unless the C<type> is
specified.  C<open> carries options for the manager, which are
described here, but may have additional options for each type of
folders.  See the options to the constructor (the C<new> method) for
each type of mail-box, but first the C<new> of C<Mail::Box> for the
general options.

The options which are most common to C<open()>:

=over 4

=item * folder =E<gt> FOLDERNAME

Which folder to open.  The default folder is $ENV{MAIL}.

=item * folderdir =E<gt> DIRECTORY

The directory where the folders are usually stored.

=item * type =E<gt> FOLDERTYPENAME|FOLDERTYPE

Specify that the folder is of a specific type.  When you do not specify this
and you open the folder for ready, it checks all registered folder-types
for the ability to open the folder.  If you open a new folder to write, then
the default will be the most recently registered type (if you add more than
one type at once, the first of the list is taken).

Examples:

   $manager->open(folder => '=jack', type => 'mbox');
   $manager->open(type => 'Mail::Box::Mbox');

=item * create =E<gt> BOOL

Create the folder when it does not exist.  By default, this is not done.
The C<type>-option specifies which type of folder is created.

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

Returns folder when the FOLDER is kept open.

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
the C<save_on_exit> flag to each seperate folder).  The folder's messages
will be withdrawn from the known message-threads.

You may also close the folder directly.  The manager will be informed
about this event and take its actions.

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

Append one or more messages to a folder.  As first argument, you
may specify a FOLDERNAME or an opened folder.  When the name is
that of an opened folder, is it treated as if the folder-structure
was specified.  You may also specify the foldername as part
of the option-list.

When a message is added to an opened folder, it is only added to
the structure internally in the program.  The data will not be
written to disk until a write of that folder takes place.  When the
name of an unopened folder is given, data message data is immediately
stored on disk.

A message must be an instance of an C<MIME::Entity>.  The actual type
may be in conflict with the requirements for the folder-type where
the data is added.  However, this is not a concern of the caller:
the folders will try to resolve the differences with minimal loss of
information.

The OPTIONS is a list of key-values, which are added to (overruling)
the default options for the detected folder-type.

Examples:

   $mgr->appendMessages('=send', $message, folderdir => '/');
   $mgr->appendMessages('=received', $inbox->messages);
   $mgr->appendMessages($inbox->messages, folder => 'Drafts');

=cut

sub appendMessage(@) {shift->appendMessages(@_)}

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

Copy a message from one folder into an other folder.  If that other folder
has not been opened, the copy behaves like an appendMessage().  Otherwise,
the data from the message is copied and added to the other open folder.

You need to specify a folder's name or folder-object as first argument,
or in the option-list.  The options are those which can be specified
when opening a folder.

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

Move a message from one folder to the next.  Be warned that removals from
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
are those of C<open()>.

To accomplish a full removal, all folders have to be opened first, while
Mail::Box messages may have parts of them stored in external files, which
must be removed too.

=cut

sub delete($@)
{   my ($self, $name, @options) = @_;
    my $folder = $self->open(folder => $name, @options) or return;
    $folder->delete;
}

#-------------------------------------------

=back

=head1 METHODS to handle threaders

=over 4

=cut

#-------------------------------------------

=item threads OPTIONS

Create a new object which keeps track on message threads.  You can read
about the possible options in the Mail::Box::Threads manpage.

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

Signal to the manager that all thread-managers which are using the
specified folder must be informed that new messages are
coming in (respectively going out).

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

This code is beta, version 1.321

=cut

1;
