
use strict;
use warnings;

package Mail::Box::Manage::User;
use base 'Mail::Box::Manager';

use Mail::Box::Collection     ();

#-------------------------------------------

=chapter NAME

Mail::Box::Manage::User - manage the folders of a user

=chapter SYNOPSIS

 use Mail::Box::Manage::User;
 use User::Identity;

 my $id      = User::Identity->new(...);
 my $user    = Mail::Box::Manage::User->new
   ( identity  => $id
   , folderdir => "$ENV{HOME}/Mail"
   , inbox     => $ENV{MAIL}
   );

 my $inbox   = $user->open($user->inbox);
 my $top     = $user->topfolder;

=chapter DESCRIPTION

Where the M<Mail::Box::Manager> takes care of some set of open folder,
this extension will add knowledge about some related person.  At the
same time, it will try to cache some information about that person's
folder files.

=chapter METHODS

=c_method new $args

Use M<new(default_folder_type)> to explicitly state which kind of folders
you use.

=requires identity OBJECT
The main difference between the M<Mail::Box::Manager> and this class, is
the concept of some person (or virtual person) who's files are being
administered by this object.  The OBJECT is an M<User::Identity>.

The smallest identity that will do:
C<< my $id = User::Identity->new('myname') >>

=option  folder_id_type CLASS|OBJECT
=default folder_id_type M<Mail::Box::Identity>

=option  topfolder_name STRING
=default topfolder_name C<'='>

=option  inbox          NAME
=default inbox          C<undef>
The name of the user's inbox.

=option  collection_type CLASS
=default collection_type M<Mail::Box::Collection>
Subfolders grouped together.

=option  delimiter      STRING
=default delimiter      "/"
The separator used in folder names.  This doesn't need to be the
same as your directory system is using.

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args) or return ();

    my $identity = $self->{MBMU_id} = $args->{identity};
    defined $identity or die;

    my $top     = $args->{folder_id_type}  || 'Mail::Box::Identity';
    my $coltype = $args->{collection_type} || 'Mail::Box::Collection';

    unless(ref $top)
    {   my $name = $args->{topfolder_name};
        $name    = '=' unless defined $name;   # MailBox's abbrev to top

        $top     = $top->new
         ( name        => $name
         , manager     => $self
         , location    => scalar($self->folderdir)
         , folder_type => $self->defaultFolderType
         , collection_type => $coltype
         );
    }

    $self->{MBMU_topfolder} = $top;
    $self->{MBMU_delim}     = $args->{delimiter} || '/';
    $self->{MBMU_inbox}     = $args->{inbox};

    $self;
}

#-------------------------------------------

=section Attributes

=method identity
Returns a M<User::Identity> object.
=cut

sub identity() { shift->{MBMU_id} }

#-------------------------------------------

=method inbox [$name]
(Set and) get the $name of the mailbox which is considered the folder
for incoming mail.  In many protocols, this folder is handled separately.
For instance in IMAP this is the only case-insensitive folder name.
=cut

sub inbox(;$)
{   my $self = shift;
    @_ ? ($self->{MBMU_inbox} = shift) : $self->{MBMU_inbox};
}

#-------------------------------------------

=section Manage open folders
=cut

# A lot of work still has to be done here: all moves etc must inform
# the "existence" administration as well.

#-------------------------------------------

=section Manage existing folders

=method topfolder
Returns the top folder of the user's mailbox storage.
=cut

sub topfolder() { shift->{MBMU_topfolder} }

#-------------------------------------------

=method folder $name
Returns the folder description, a M<Mail::Box::Identity>.
=cut

sub folder($)
{   my ($self, $name) = @_;
    my $top  = $self->topfolder or return ();
    my @path = split $self->{MBMU_delim}, $name;
    return () unless shift @path eq $top->name;

    $top->folder(@path);
}

#-------------------------------------------

=method folderCollection $name
Returns a pair: the folder collection (M<Mail::Box::Collection>) and
the base name of $name.
=cut

sub folderCollection($)
{   my ($self, $name) = @_;
    my $top  = $self->topfolder or return ();

    my @path = split $self->{MBMU_delim}, $name;
    unless(shift @path eq $top->name)
    {   $self->log(ERROR => "Folder name $name not under top.");
        return ();
    }

    my $base = pop @path;

    ($top->folder(@path), $base);
}

#-------------------------------------------

=method create $name, %options
Creates a new folder with the specified name.  An folder's administrative
structure (M<Mail::Box::Identity>) is returned, but the folder is not
opened.

In the accidental case that the folder already
exists, a warning will be issued, and an empty list/undef returned.

The %options are passed to M<Mail::Box::create()> of your default folder
type, except for the options intended for this method itself.

=option  id_options    ARRAY
=default id_options    []
Values passed to the instantiated M<Mail::Box::Identity>.  That object
is very picky about the initiation values it accepts.

=option  create_supers BOOLEAN
=default create_supers <false>
When you create a folder where upper hierarchy level are missing, they
will be created as well.

=option  deleted      BOOLEAN
=default deleted      <false>
The folder starts as deleted.

=option  create_real  BOOLEAN
=default create_real  <true>
When this option is false, the pysical folder will not be created, but
only the administration is updated.

=error Cannot create $name: higher levels missing
Unless you set M<create(create_supers)>, all higher level folders must
exist before this new one can be created.
=cut

# This feature is thoroughly tested in the Mail::Box::Netzwert distribution

sub create($@)
{   my ($self, $name, %args) = @_;
    my ($dir, $base) = $self->folderCollection($name);

    unless(defined $dir)
    {   unless($args{create_supers})
        {   $self->log(ERROR => "Cannot create $name: higher levels missing");
            return undef;
        }

        (my $upper = $name) =~ s!$self->{MBMU_delim}$base!!
             or die "$name - $base";

        $dir = $self->create($upper, %args, deleted => 1);
    }

    my $id = $dir->folder($base);
    if(!defined $id)
    {   my $idopt= $args{id_options} || [];
        $id  = $dir->addSubfolder($base, @$idopt, deleted => $args{deleted});
    }
    elsif($args{deleted})
    {   $id->deleted(1);
        return $id;
    }
    elsif($id->deleted)
    {   # Revive! Raise the death!
        $id->deleted(0);
    }
    else
    {   # Bumped into existing folder
        $self->log(ERROR => "Folder $name already exists");
        return undef;
    }

    if(!defined $args{create_real} || $args{create_real})
    {   $self->defaultFolderType->create($id->location, %args)
           or return undef;
    }

    $id;
}

#-------------------------------------------
                                                                                
=method delete $name
Remove all signs from the folder on the file-system.  Messages still in
the folder will be removed.  This method returns a true value when the
folder has been removed or not found, so "false" means failure.

It is also possible to delete a folder using C<< $folder->delete >>,
which will call this method here.  OPTIONS, which are used for some
other folder types, will be ignored here: the user's index contains the
required details.

=example how to delete a folder
 print "no xyz (anymore)\n" if $user->delete('xyz');

=error Unable to remove folder $dir
=cut

sub delete($)
{   my ($self, $name) = @_;
    my $id = $self->folder($name) or return ();
    $id->remove;

    $self->SUPER::delete($name);
}

#-------------------------------------------

=method rename $oldname, $newname, %options
Rename the folder with name $oldname to $newname.  Both names are full
pathnames.

=option  create_supers BOOLEAN
=default create_supers <false>
When you rename a folder to a place where upper hierarchy levels are
missing, they will get be defined, but with the deleted flag set.

=error Cannot rename $name to $new: higher levels missing
Unless you set M<create(create_supers)>, all higher level folders must
exist before this new one can be created.
=cut

sub rename($$@)
{   my ($self, $oldname, $newname, %args) = @_;

    my $old     = $self->folder($oldname);
    unless(defined $old)
    {   $self->log(WARNING
            => "Source for rename does not exist: $oldname to $newname");
        return ();
    }

    my ($newdir, $base) = $self->folderCollection($newname);
    unless(defined $newdir)
    {   unless($args{create_supers})
        {   $self->log(ERROR
               => "Cannot rename $oldname to $newname: higher levels missing");
            return ();
        }

        (my $upper = $newname) =~ s!$self->{MBMU_delim}$base!!
             or die "$newname - $base";

        $newdir = $self->create($upper, %args, deleted => 1);
    }

    my $oldlocation = $old->location;
    my $new         = $old->rename($newdir, $base);

    my $newlocation = $new->location;
    if($oldlocation ne $newlocation)
    {   require Carp;
        croak("Physical folder relocation not yet implemented");
# this needs a $old->rename(xx,yy) which isn't implemented yet
    }

    $self->log(PROGRESS => "Renamed folder $oldname to $newname");
    $new;
}

#-------------------------------------------

=section Move messages to folders

=section Internals

=section Error handling

=cut

1;
