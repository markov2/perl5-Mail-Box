
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
use FileHandle;
use File::Copy;
use File::Spec;
use File::Basename;

=head1 NAME

Mail::Box::Net - handle folders which are stored remote.

=head1 SYNOPSIS

 # Do not instantiate this object yourself

=head1 DESCRIPTION

This documentation describes how directory organized mailboxes work.
Please read C<Mail::Box-Overview> first.

At the moment, this object is extended by

=over 4

=item * POP3

=back

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=default body_type 'Mail::Message::Body::Lines'
=default lock_type <not used>
=default lock_file <not used>
=default lock_timeout <not used>
=default lock_wait <not used>
=default remove_when_empty <false>

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
{   my ($self, $args)    = @_;

    $args->{body_type} ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);

    $self->{MBN_username} = $args->{username};
    $self->{MBN_password} = $args->{password};
    $self->{MBN_hostname} = $args->{server_name};
    $self->{MBN_port}     = $args->{server_port};

    $self;
}

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

sub organization() { 'REMOTE' }

#-------------------------------------------

1;
