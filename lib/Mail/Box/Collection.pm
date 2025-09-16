#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Collection;
use base qw/User::Identity::Collection Mail::Reporter/;

use strict;
use warnings;

use Mail::Box::Identity;

use Scalar::Util    qw/weaken/;

#--------------------
=chapter NAME

Mail::Box::Collection - a collection of subfolders

=chapter SYNOPSIS

=chapter DESCRIPTION

The Mail::Box::Collection object maintains a set Mail::Box::Identity
objects, each describing a the location of a single mailbox (folder).  The
collection is used by the Mail::Box::Manage::User object to administer
the folders of a single user, even if those folders are closed.

=chapter METHODS

=c_method new [$name], %options

=default  name      C<'folders'>
=default  item_type Mail::Box::Identity

=option   manager   OBJECT
=default  manager   <from parent>
An Mail::Box::Manager OBJECT (could be a Mail::Box::Manage::User).

=option   folder_type CLASS
=default  folder_type <from parent>

=cut

sub new(@)
{	my $class = shift;
	unshift  @_,'name' if @_ % 2;
	$class->Mail::Reporter::new(@_);
}

sub init($)
{	my ($self, $args) = @_;
	$args->{item_type} //= 'Mail::Box::Identity';

	$self->Mail::Reporter::init($args);
	$self->User::Identity::Collection::init($args);

	weaken($self->{MBC_manager})
		if $self->{MBC_manager} = delete $args->{manager};

	$self->{MBC_ftype} = delete $args->{folder_type};
	$self;
}

#--------------------
=section Attributes
=cut

sub type() { 'folders' }

=method manager
The Mail::Box::Manager (usually a Mail::Box::Manage::User object),
which is handling the opening of folders.
=cut

sub manager()
{	my $self = shift;
	return $self->{MBC_manager}
		if defined $self->{MBC_manager};

	my $parent = $self->parent;
	defined $parent ? $self->parent->manager : undef;
}

=method folderType [$folderclass]
Returns the type of folder (on this location).  When specified, then
$folderclass must be a Mail::Box extension.
=cut

sub folderType()
{	my $self = shift;
	return ($self->{MBC_ftype} = shift) if @_;
	return $self->{MBC_ftype} if exists $self->{MBC_ftype};

	if(my $parent = $self->parent)
	{	return $self->{MBC_ftype} = $parent->folderType;
	}

	undef;
}

1;
