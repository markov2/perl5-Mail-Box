
use strict;
package Mail::Box::Net;

use base 'Mail::Box';

use Mail::Box::Net::Message;

use Mail::Message::Body::Lines;
use Mail::Message::Body::File;
use Mail::Message::Body::Delayed;
use Mail::Message::Body::Multipart;

use Mail::Message::Head;
use Mail::Message::Head::Delayed;

use Carp;
use File::Copy;
use File::Spec;
use File::Basename;

=head1 NAME

Mail::Box::Net - handle folders which are stored remote.

=head1 SYNOPSIS

 # Do not instantiate this object yourself

=head1 DESCRIPTION

At the moment, this object is extended by

=over 4

=item * Mail::Box::POP3

=item * Mail::Box::IMAP4

UNDER DEVELOPMENT

=back

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=default body_type 'Mail::Message::Body::Lines'

=default folderdir <not used>
=default lock_type 'NONE'
=default remove_when_empty <false>
=default trusted <false>
=default folder '/'

=option  server_name HOSTNAME
=default server_name undef

The name of the host which contains the remote mail server.

=option  password STRING
=default password undef

The password which is required to contact the remote server.

=option  username STRING
=default username undef

The username which is to be used for the remote server.

=option  server_port INTEGER
=default server_port undef

Port number in use by the server application.

=cut

sub init($)
{   my ($self, $args)     = @_;

    $args->{lock_type}  ||= 'NONE';
    $args->{body_type}  ||= 'Mail::Message::Body::Lines';
    $args->{folder}     ||= '/';
    $args->{trusted}    ||= 0;

    $self->SUPER::init($args);

    $self->{MBN_username} = $args->{username};
    $self->{MBN_password} = $args->{password};
    $self->{MBN_hostname} = $args->{server_name};
    $self->{MBN_port}     = $args->{server_port};

    $self;
}

#-------------------------------------------

=head2 Opening folders

=cut

#-------------------------------------------

=method create FOLDER, OPTIONS

Create a new folder on the remote server.

=default folderdir <not used>

=cut

sub create(@) {shift->notImplemented}

#-------------------------------------------

=method folderdir [DIRECTORY]

Not applicatable for folders on a remote server, so will always return
the C<undef>.

=cut

sub folderdir(;$) { undef }

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

sub organization() { 'REMOTE' }

#-------------------------------------------

sub url()
{   my $self = shift;

    my ($user, $pass, $host, $port)
       = @$self{ qw/MBN_username MBN_password MBN_hostname MBN_port/ };

    my $perm = '';
    $perm    = $user if defined $user;
    if(defined $pass)
    {   $pass  =~ s/(\W)/sprintf "%%%02X", ord $1/ge;
        $perm .= ':'.$pass;
    }

    $perm   .= '@'       if length $perm;

    my $loc  = $host;
    $loc    .= ':'.$port if length $port;

    my $name = $self->name;
    $loc    .= '/'.$name if $name ne '/';
    
    $self->type . '://' . $perm . $loc;
}

#-------------------------------------------

1;
