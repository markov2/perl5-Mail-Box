use strict;
use warnings;

package Mail::Box::Identity;
use base qw/User::Identity::Item Mail::Reporter/;

use Mail::Box::Collection;

# tests in tests/52message/30collect.t

=chapter NAME

Mail::Box::Identity - represents an unopened folder

=chapter SYNOPSIS

 use M<User::Identity>;
 use Mail::Box::Identity;
 my $me   = User::Identity->new(...);

 my $mailbox = Mail::Box::Identity->new(...);
 $me->add(folders => $mailbox);

 # Simpler

 use User::Identity;
 my $me   = User::Identity->new(...);
 my $addr = $me->add(folders => ...);

=chapter DESCRIPTION
The C<Mail::Box::Identity> object contains the description of a
single mailbox.  The mailboxes are collected by an M<Mail::Box::Collection>
object.  This corresponds with IMAP's C<\NoSelect>, for instance.

Nearly all methods can return undef.

=chapter METHODS

=cut

sub type { "mailbox" }

=c_method new [$name], %options

=option  folder_type CLASS
=default folder_type C<from parent>

=option  location    DIRECTORY|FILENAME
=default location    C<undef>
The location of this folder.  Often, only the manager can figure-out
where this folder really is.

=option   only_subs   BOOLEAN
=default  only_subs   <foldertype and name dependent>
Some folder types can have messages in their toplevel folder, other
cannot. That determines the default.
See M<Mail::Box::topFolderWithMessages()>

=option   manager     OBJECT
=default  manager     <from parent>
Any M<Mail::Box::Manager> or M<Mail::Box::Manage::User> OBJECT.

=option   subf_type   CLASS
=default  subf_type   <same as parent>
The type for a subfolder collection, must extend CLASS
M<Mail::Box::Collection>.

=option   marked      BOOLEAN|C<undef>
=default  marked      C<undef>
Whether the folder is flagged for some reason, for instance because
new messages have arrived.

=option   inferiors   BOOLEAN
=default  inferiors   1
Can this folder have children?  If not, this is cleared.

=option   deleted BOOLEAN
=default  deleted <false>
The folder is flagged for deletion.  This not have any implications yet,
because it may still get undeleted.

=cut

sub new(@)
{   my $class = shift;
    unshift @_, 'name' if @_ % 2;
    $class->Mail::Reporter::new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->Mail::Reporter::init($args);
    $self->User::Identity::init($args);

    $self->{MBI_location}  = delete $args->{location};
    $self->{MBI_ftype}     = delete $args->{folder_type};
    $self->{MBI_manager}   = delete $args->{manager};
    $self->{MBI_subf_type} = delete $args->{subf_type}||'Mail::Box::Collection';
    $self->{MBI_only_subs} = delete $args->{only_subs};
    $self->{MBI_marked}    = delete $args->{marked};
    $self->{MBI_deleted}   = delete $args->{deleted};
    $self->{MBI_inferiors} = exists $args->{inferiors} ? $args->{inferiors} : 1;

    $self;
}

#-------------------------------------------

=section Attributes

=method fullname [$delimeter]
Returns the name of the folder, from the toplevel until this one, with
the $delimeter string between each level.  $delimeter default to a forward
slash (a C</>).
=cut

sub fullname(;$)
{   my $self   = shift;
    my $delim  = @_ && defined $_[0] ? shift : '/';

    my $parent = $self->parent or return $self->name;
    $parent->parent->fullname($delim) . $delim . $self->name;
}

#-------------------------------------------

=method location [$filename|$directory|undef]
Returns the directory or filename of the folder.  If this is not pre-defined,
it is computed based on the knowledge about the folder type.  Be sure to set
the location of the toplevel folder to the folderdir of the user to get
this to work.

=error Toplevel directory requires explicit location
=cut

sub location(;$)
{   my $self = shift;
    return ($self->{MBI_location} = shift) if @_;
    return $self->{MBI_location} if defined $self->{MBI_location};

    my $parent = $self->parent;
    unless(defined $parent)
    {   $self->log(ERROR => "Toplevel directory requires explicit location");
        return undef;
    }

    $self->folderType
         ->nameOfSubFolder($self->name, $parent->parent->location)
}

#-------------------------------------------

=method folderType
Returns the type of this folder.
=error Toplevel directory requires explicit folder type
=cut

sub folderType()
{   my $self = shift;
    return $self->{MBI_ftype} if defined $self->{MBI_ftype};

    my $parent = $self->parent;
    unless(defined $parent)
    {   $self->log(ERROR => "Toplevel directory requires explicit folder type");
        return undef;
    }

    $parent->parent->folderType;
}

#-------------------------------------------

=method manager
Returns the manager (usually a M<Mail::Box::Manage::User> which owns
the folders.  May be undefined, by default from parent.
=cut

sub manager()
{    my $self = shift;
     return $self->{MBI_manager} if $self->{MBI_manager};
     my $parent = $self->parent or return undef;
     $self->parent->manager;
}

#-------------------------------------------

=method topfolder
Run up the tree to find the highest level folder.
=cut

sub topfolder()
{   my $self = shift;
    my $parent = $self->parent or return $self;
    $parent->parent->topfolder;
}

#-------------------------------------------

=method onlySubfolders [BOOLEAN]
Than this folder be opened (without trying) or not?  The default
depends on the folder type, and whether this is the toplevel folder
or not.  See M<Mail::Box::topFolderWithMessages()>
=cut

sub onlySubfolders(;$)
{   my $self = shift;
    return($self->{MBI_only_subs} = shift) if @_;
    return $self->{MBI_only_subs} if exists $self->{MBI_only_subs};
    $self->parent ? 1 : ! $self->folderType->topFolderWithMessages;
}

#-------------------------------------------

=method marked [BOOLEAN|undef]
When something special has happened with the folder, this flag can
be set (or cleared).  The C<undef> status is an "unknown".  In the
IMAP4 protocol, C<0> will result in a C<\Unmarked>, a C<1> results
in a C<\Marked>, and C<undef> in nothing.
=cut

sub marked(;$)
{   my $self = shift;
    @_ ? ($self->{MBI_marked} = shift) : $self->{MBI_marked};
}

#-------------------------------------------

=method inferiors [BOOLEAN]
C<Inferiors> are C<subfolders>.  When this flag is set, it is permitted
to create subfolders.
=cut

sub inferiors(;$)
{   my $self = shift;
    @_ ? ($self->{MBI_inferiors} = shift) : $self->{MBI_inferiors};
}

#-------------------------------------------
                                                                                
=section Attributes
                                                                                
=method deleted [BOOLEAN]
=cut

sub deleted(;$)
{   my $self = shift;
    @_ ? ($self->{MBI_deleted} = shift) : $self->{MBI_deleted};
}
                                                                                
#-------------------------------------------

=section Subfolders

=method subfolders
Returns the subfolders or C<undef> if there are none.  This
information is lazy evaluated and cached.  In LIST context, the folder
objects are returned (M<Mail::Box::Identity> objects), in SCALAR context
the collection, the M<Mail::Box::Collection>.
=cut

sub subfolders()
{   my $self = shift;
    my $subs = $self->collection('subfolders');
    return (wantarray ? $subs->roles : $subs)
        if defined $subs;

    my @subs;
    if(my $location = $self->location)
    {   @subs  = $self->folderType->listSubFolders
         ( folder    => $location
         );
    }
    else
    {   my $mgr   = $self->manager;
        my $top   = defined $mgr ? $mgr->folderdir : '.';

        @subs  = $self->folderType->listSubFolders
          ( folder    => $self->fullname
          , folderdir => $top
          );
    }
    @subs or return ();

    my $subf_type
      = $self->{MBI_subf_type} || ref($self->parent) || 'Mail::Box::Collection';

    $subs = $subf_type->new('subfolders');

    $self->addCollection($subs);
    $subs->addRole(name => $_) for @subs;
    wantarray ? $subs->roles : $subs;
}

#-------------------------------------------

=method subfolderNames
Convenience method: returns the names of the collected subfolders.
=cut

sub subfolderNames() { map {$_->name} shift->subfolders }

#-------------------------------------------

=method folder [..., $name]
Returns the subfolder's object with $name or C<undef> if it does not
exist.  When multiple NAMEs are added, those super folders are traverst
first.  Without any $name, the current object is returned

=examples get some folder
 my $a = $user->folders->folder('b', 'a');

 my $name  = "a:b:c";
 my $delim = ":";
 my $f = $user->folders->folder(split $delim, $name);

=cut

sub folder(@)
{   my $self = shift;
    return $self unless @_ && defined $_[0];

    my $subs = $self->subfolders  or return undef;
    my $nest = $subs->find(shift) or return undef;
    $nest->folder(@_);
}

#-------------------------------------------

=method open %options
Open the folder which is described by this identity.  Returned is some
M<Mail::Box>.  The options are passed to M<Mail::Box::Manager::open()>.
=cut

sub open(@)
{   my $self = shift;
    $self->manager->open($self->fullname, type => $self->folderType, @_);
}

#-------------------------------------------

=method foreach CODE
For each of the subfolders found below this point call CODE.  This current
folder is called first.  Be warned that you may find identities with
the M<deleted()> flag on.
=cut

sub foreach($)
{   my ($self, $code) = @_;
    $code->($self);

    my $subs = $self->subfolders or return ();
    $_->foreach($code) for $subs->sorted;
    $self;
}

#-------------------------------------------

=method addSubfolder $m<Mail::Box::Identity>|$data
Add a new folder into the administration.  With $data, a new object
will be instantiated first.  The identity is returned on success.

=error It is not permitted to add subfolders to $name
The $m<inferiors()> flag prohibits the creation of subfolders to this
folder.
=cut

sub addSubfolder(@)
{   my $self  = shift;
    my $subs  = $self->subfolders;

    if(defined $subs) { ; }
    elsif(!$self->inferiors)
    {   my $name = $self->fullname;
        $self->log(ERROR => "It is not permitted to add subfolders to $name");
        return undef;
    }
    else
    {   $subs = $self->{MBI_subf_type}->new('subfolders');
        $self->addCollection($subs);
    }

    $subs->addRole(@_);
}

#-------------------------------------------

=method remove [$name]
Remove the folder (plus subfolders) with the $name.  Without $name, this
C<Mail::Box::Identity> itself is removed.

The removed structure is returned, which is C<undef> if not
found.  This is only an administrative remove, you still need a
M<Mail::Box::Manager::delete()>.

=error The toplevel folder cannot be removed this way
The M<Mail::Box::Identity> folder administration structure requires
a top directory.  That top is registered somewhere (for instance
by a M<Mail::Box::Manage::User>).  If you need to remove the top,
you have to look for a method of that object.
=cut

sub remove(;$)
{   my $self = shift;

    my $parent = $self->parent;
    unless(defined $parent)
    {   $self->log(ERROR => "The toplevel folder cannot be removed this way");
        return ();
    }

    return $parent->removeRole($self->name)
        unless @_;

    my $name = shift;
    my $subs = $self->subfolders or return ();
    $subs->removeRole($name);
}

#-------------------------------------------

=method rename $folder, [$newsubname]
Move the folder to a different super-$folder, under a NEW SUBfolder NAME.

=example renaming a folder
 my $top = $user->topfolder;
 my $new = $top->folder('xyz') or die;
 my $f   = $top->folder('abc', 'def')->rename($new, '123');

 print $f->name;      # 123
 print $f->fullname;  # =/xyz/123

=cut

sub rename($;$)
{   my ($self, $folder, $newname) = @_;
    $newname = $self->name unless defined $newname;

    my $away = $self->remove;
    $away->name($newname);

    $folder->addSubfolder($away);
}

=section Error handling
=cut

1;


