use strict;
use warnings;

package Mail::Box::Collection;
use base qw/User::Identity::Collection Mail::Reporter/;

use Mail::Box::Identity;

use Scalar::Util    qw/weaken/;

=chapter NAME

Mail::Box::Collection - a collection of subfolders

=chapter SYNOPSIS

=chapter DESCRIPTION

The M<Mail::Box::Collection> object maintains a set M<Mail::Box::Identity>
objects, each describing a the location of a single mailbox (folder).  The
collection is used by the M<Mail::Box::Manage::User> object to administer
the folders of a single user, even if those folders are closed.

=chapter METHODS

=c_method new [$name], %options

=default  name      C<'folders'>
=default  item_type M<Mail::Box::Identity>

=option   manager   OBJECT
=default  manager   <from parent>
An M<Mail::Box::Manager> OBJECT (could be a M<Mail::Box::Manage::User>).

=option   folder_type CLASS
=default  folder_type <from parent>

=cut

sub new(@)
{   my $class = shift;
    unshift  @_,'name' if @_ % 2;
    $class->Mail::Reporter::new(@_);
}
                                                                                
sub init($)
{   my ($self, $args) = @_;
    $args->{item_type} ||= 'Mail::Box::Identity';

    $self->Mail::Reporter::init($args);
    $self->User::Identity::Collection::init($args);
                                                                                
    weaken($self->{MBC_manager})
       if $self->{MBC_manager}  = delete $args->{manager};
    
    $self->{MBC_ftype}    = delete $args->{folder_type};
    $self;
}

sub type() { 'folders' }

#------------------------------------------

=section Attributes

=method manager
The M<Mail::Box::Manager> (usually a M<Mail::Box::Manage::User> object),
which is handling the opening of folders.
=cut

sub manager()
{   my $self = shift;
    return $self->{MBC_manager}
        if defined $self->{MBC_manager};

    my $parent = $self->parent;
    defined $parent ? $self->parent->manager : undef;
}

#------------------------------------------

=method folderType [$folderclass]
Returns the type of folder (on this location).  When specified, then
$folderclass must be a M<Mail::Box> extension.
=cut

sub folderType()
{   my $self = shift;
    return($self->{MBC_ftype} = shift) if @_;
    return $self->{MBC_ftype} if exists $self->{MBC_ftype};

    if(my $parent = $self->parent)
    {   return $self->{MBC_ftype} = $parent->folderType;
    }

    undef;
}

#------------------------------------------

1;

