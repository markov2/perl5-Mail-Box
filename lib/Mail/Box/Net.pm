
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

=chapter NAME

Mail::Box::Net - handle folders which are stored remote.

=chapter SYNOPSIS

 # Do not instantiate this object directly

=chapter DESCRIPTION

At the moment, this object is extended by

=over 4

=item * M<Mail::Box::POP3>

Implements the POP3 protocol.

=item * M<Mail::Box::IMAP4>

Implements the IMAP4 protocol.  B<UNDER DEVELOPMENT>

=back

=chapter METHODS

=c_method new %options

=default body_type M<Mail::Message::Body::Lines>
=default folderdir <not used>
=default lock_type C<'NONE'>
=default remove_when_empty <false>
=default trusted   <false>
=default folder    C<'/'>

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

    $self->log(WARNING => "The term 'hostname' is confusing wrt folder. You probably need 'server_name'")
         if exists $args->{hostname};

    $self;
}

#-------------------------------------------

=ci_method create $folder, %options

Create a new folder on the remote server.

=default folderdir <not used>

=cut

sub create(@) {shift->notImplemented}

#-------------------------------------------

=method folderdir [$directory]

Not applicatable for folders on a remote server, so will always return
the C<undef>.

=cut

sub folderdir(;$) { undef }

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
