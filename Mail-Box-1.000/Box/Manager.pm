
use strict;
package Mail::Box::Manager;

use Mail::Box;

=head1 NAME

Mail::Box::Manager - Manage a set of folders

=head1 SYNOPSIS

   use Mail::Box::Manager;
   my $manager = new Mail::Box::Manager;
   my $folder  = $manager->open(folder => $ENV{MAIL});
   $manager->registerType(mbox => 'Mail::Box::Mbox');
   $manager->close($folder);

=head1 DESCRIPTION

This code is beta, which means that there are no serious applications
written with it yet.  Please inform the author when you have, so this
module can go to stable.  Read the STATUS file inclosed in the package for
more details.

The folder manager maintains a set of folders (mail-boxes).  Those
folders may be of different types.  Most folder-types can be detected
automatically.

This class is the only one you create in your program: all other classes
will come when needed.

Overview:

  Mail::Box::Manager
        |
        | open()
        |              message()
        v             ,--------->  Mail::Box::Message
     Mail::Box      /                    isa
  (Mail::Box::Mbox)                  MIME::Entity
   (Mail::Box::MH)                   : :
    : : :                            : :
    : : :                            : Mail::Box::Message::Dummy
    : : :                            Mail::Box::Message::NotParsed
    : : Mail::Box::Tie
    : Mail::Box::Threads
    Mail::Box::Locker

All classes are written to be extendible.  The most complicated work
is done in MIME::Entity, which is written and maintained by
Eryq (eryq@zeegee.com).

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

(class method) Create a new folder folder-manager.  This constructor
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
    $self->registerType(@$_) foreach @types, @basic_folder_types;

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

    $self->{MBM_open_folders} = [];
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

    # Do not open twice.
    my ($folder) = grep {$name eq "$_"} $self->openFolders;
    if($folder)
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

            $self->addOpenFolder($folder) if $folder;
            return $folder;
        }
        warn "I do not know foldertype $args{type}: autodecting.";
    }

    # Try to autodetect foldertype.
    my @find_options;
    push @find_options, folderdir => $args{folderdir};

    foreach (@{$self->{MBM_folder_types}})
    {   my ($type, $class, @options) = @$_;
        push @options, manager => $self;
        next unless $class->foundIn($name, @find_options);
        return $self->addOpenFolder($class->new(@options, %args));
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

=item addOpenFolder FOLDER

=item openFolders

As could be expected from the name, C<addOpenFolder> adds a new folder to
set of open folders.  Ignores undefined value for FOLDER.
C<openFolders> returns a list of all open folders.

=cut

sub addOpenFolder(@)
{   my ($self, $folder) = @_;
    push @{$self->{MBM_open_folders}}, $folder if $folder;
    $folder;
}

sub openFolders() { @{shift->{MBM_open_folders}} }

#-------------------------------------------

=item close FOLDER

=item closeAllFolders

C<close> removes the specified folder from the list of open folders.
Indirectly it will update the files on disk if needed (depends on
the C<save_on_exit> flag to each seperate folder).

You may also close the folder directly.  The manager will be informed
about this event.

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

    my @open   = $self->openFolders;
    my @result = grep {$folder ne $_} @open;

    if(@result==@open)
    {   warn "The folder was not opened by this folder-manager.\n";
        return;
    }

    $folder->close;
    $self->{MBM_open_folders} = [ @result ];
    $self;
}

sub closeAllFolders()
{   my $self = shift;
    $_->close foreach $self->openFolders;
    $self;
}

#-------------------------------------------

=item appendMessage FOLDER|FOLDERNAME, MESSAGES, OPTIONS

Append one or more messages to a folder.  As first argument, you
may specify a FOLDERNAME or an opened folder.  When the name is
that of an opened folder, is it treated as if the folder-structure
was specified.

When a message is added to an opened folder, it is only added to
the structure internally in the program.  The data will not be
written to disk until a write of that folder takes place.  When the
name of an unopened folder is given, data message data is immediately
stored on disk.

A message must be an instance of an MIME::Entity.  The actual type
may be in conflict with the requirements for the folder-type where
the data is added.  However, this is not a concern of the caller:
the folders will try to resolve the differences with minimal loss of
information.

The OPTIONS is a list of key-values, which are added to (overruling)
the default options for the detected folder-type.

Examples:

   $mgr->appendMessage('=send', $message, folderdir => '/');
   $mgr->appendMessage('=received', $inbox->messages);

=cut

sub appendMessage($@)
{   my ($self, $folder) = (shift, shift);
    my @messages;
    push @messages, shift while @_ && ref $_[0];
    my @options = @_;

    # Try to resolve filenames into opened-files.
    unless(ref $folder)
    {   foreach ($self->openFolders)
        {   if($_->name eq $folder)
            {   $folder = $_;
                last;
            }
        }
    }

    if(ref $folder)
    {   # An open file.
        unless($folder->isa('Mail::Box'))
        {   warn "Folder $folder is not a Mail::Box; cannot add a message.\n";
            return;
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
      ( folder   => $folder
      , type     => $name
      , messages => \@messages
      , @gen_options
      , @options
      );
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

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.000

=cut

1;
