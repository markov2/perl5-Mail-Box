
use strict;
use warnings;

package Mail::Transport::POP3;
use base 'Mail::Transport::Receive';

use IO::Socket  ();
use Socket      qw/$CRLF/;
use Digest::MD5 ();

=chapter NAME

Mail::Transport::POP3 - receive messages via POP3

=chapter SYNOPSIS

 my $receiver = Mail::Transport::POP3->new(...);
 my $message = $receiver->receive($id);

=chapter DESCRIPTION

Receive messages via the POP3 protocol from one remote server, as specified
in rfc1939.  This object hides much of the complications in the protocol and
recovers broken connections automatically.  Although it is part of the
MailBox distribution, this object can be used separately.

You probably should B<not use this> module, but M<Mail::Box::POP3>.  This
module is the interface to POP3, whereas M<Mail::Box::POP3> hides the
protocol weirdness and works as any other mail folder.

=chapter METHODS

=c_method new %options

Create a new pop3 server connection.  One object can only handle one
connection: for a single user to one single server.  If the server
could not be reached, or when the login fails, this instantiating C<new>
will return C<undef>.

=default port C<110>

=option  authenticate 'LOGIN'|'APOP'|'AUTO'
=default authenticate C<'AUTO'>

Authenthication method.  The standard defines two methods, named LOGIN and
APOP.  The first sends the username and password in plain text to the server
to get permission, the latter encrypts this data using MD5.  When AUTO is
used, first APOP is tried, and then LOGIN.

=option  use_ssl BOOLEAN
=default use_ssl <false>
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{via}    = 'pop3';
    $args->{port} ||= 110;

    $self->SUPER::init($args) or return;

    $self->{MTP_auth} = $args->{authenticate} || 'AUTO';
    $self->{MTP_ssl}  = $args->{use_ssl};
    return unless $self->socket;   # establish connection

    $self;
}

#------------------------------------------

=section Receiving mail

=section Exchanging information

=method ids
Returns a list (in list context) or a reference to a list (in scalar context)
of all IDs which are known by the server on this moment.
=cut

sub ids(;@)
{   my $self = shift;
    return unless $self->socket;
    wantarray ? @{$self->{MTP_n2uidl}} : $self->{MTP_n2uidl};
}

#------------------------------------------

=method messages
Returns (in scalar context only) the number of messages that are known
to exist in the mailbox.

=error Cannot get the messages of pop3 via messages()
It is not possible to retrieve all messages on a remote POP3 folder
at once: each shall be taken separately.  The POP3 folder will hide this
for you.

=cut

sub messages()
{   my $self = shift;

    $self->log(ERROR =>"Cannot get the messages of pop3 via messages()."), return ()
       if wantarray;

    $self->{MTP_messages};
}

=method folderSize
Returns the total number of octets used by the mailbox on the remote server.
=cut

sub folderSize() { shift->{MTP_total} }

=method header $id, [$bodylines]
Returns a reference to an array which contains the header of the message
with the specified $id.  C<undef> is returned if something has gone wrong.

The optional integer $bodylines specifies the number of lines from the body
which should be added, by default none.

=example
 my $ref_lines = $pop3->header($uidl);
 print @$ref_lines;

=cut

sub header($;$)
{   my ($self, $uidl) = (shift, shift);
    return unless $uidl;
    my $bodylines = shift || 0;;

    my $socket    = $self->socket      or return;
    my $n         = $self->id2n($uidl) or return;

    $self->sendList($socket, "TOP $n $bodylines$CRLF");
}

=method message $id
Returns a reference to an array which contains the lines of the
message with the specified $id.  Returns C<undef> if something has gone
wrong.

=example
 my $ref_lines = $pop3->message($uidl);
 print @$ref_lines;

=cut

sub message($;$)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $socket  = $self->socket      or return;
    my $n       = $self->id2n($uidl) or return;
    my $message = $self->sendList($socket, "RETR $n$CRLF");

    return unless $message;

    # Some POP3 servers add a trailing empty line
    pop @$message if @$message && $message->[-1] =~ m/^[\012\015]*$/;

    $self->{MTP_fetched}{$uidl} = undef   # mark this ID as fetched
        unless exists $self->{MTP_nouidl};

    $message;
}

=method messageSize $id
Returns the size of the message which is indicated by the $id, in octets.
If the message has been deleted on the remote server, this will return
C<undef>.
=cut

sub messageSize($)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $list;
    unless($list = $self->{MTP_n2length})
    {   my $socket = $self->socket or return;
        my $raw = $self->sendList($socket, "LIST$CRLF") or return;
        my @n2length;
        foreach (@$raw)
        {   m#^(\d+) (\d+)#;
            $n2length[$1] = $2;
        }   
        $self->{MTP_n2length} = $list = \@n2length;
    }

    my $n = $self->id2n($uidl) or return;
    $list->[$n];
}

=method deleted BOOLEAN, @ids
Either mark the specified message(s) to be deleted on the remote server or
unmark them for deletion (if the first parameter is false).  Deletion of
messages will take place B<only> when the connection is specifically
disconnected or the last reference to the object goes out of scope.
=cut

sub deleted($@)
{   my $dele = shift->{MTP_dele} ||= {};
    (shift) ? @$dele{ @_ } = () : delete @$dele{ @_ };
}

=method deleteFetched
Mark all messages that have been fetched with M<message()> for deletion.
See M<fetched()>.
=cut

sub deleteFetched()
{   my $self = shift;
    $self->deleted(1, keys %{$self->{MTP_fetched}});
}

=method disconnect
Break contact with the server, if that (still) exists.  Returns true if
successful.  Please note that even if the disconnect was not successful,
all knowledge of messages etc. will be removed from the object: the object
basically has reverted to the state in which it was before anything was done
with the mail box.
=cut

sub disconnect()
{   my $self = shift;

    my $quit;
    if($self->{MTP_socket}) # can only disconnect once
    {   if(my $socket = $self->socket)
        {   my $dele  = $self->{MTP_dele} || {};
            while(my $uidl = each %$dele)
            {   my $n = $self->id2n($uidl) or next;
                $self->send($socket, "DELE $n$CRLF") or last;
            }

            $quit = $self->send($socket, "QUIT$CRLF");
            close $socket;
        }
    }

    delete @$self{ qw(
     MTP_socket
     MTP_dele
     MTP_uidl2n
     MTP_n2uidl
     MTP_n2length
     MTP_fetched
    ) };

    OK($quit);
}

=method fetched
Returns a reference to a list of ID's that have been fetched using
M<message()>.  This can be used to update a database of messages that
were fetched (but maybe not yet deleted) from the mailbox.

Please note that if the POP3 server did not support the UIDL command, this
method will always return undef because it is not possibly to reliably
identify messages between sessions (other than looking at the contents of
the messages themselves).

See also M<deleteFetched()>.
=cut

sub fetched(;$)
{   my $self = shift;
    return if exists $self->{MTP_nouidl};
    $self->{MTP_fetched};
}

=method id2n $id
Translates the unique $id of a message into a sequence number which
represents the message as long a this connection to the POP3 server
exists.  When the message has been deleted for some reason, C<undef>
is returned.
=cut

sub id2n($;$) { shift->{MTP_uidl2n}{shift()} }

#------------------------------------------

=section Protocol internals

The follow methods handle protocol internals, and should not be used
by a normal user of this class.

=method socket
Returns a connection to the POP3 server.  If there was no connection yet,
it will be created transparently.  If the connection with the POP3 server
was lost, it will be reconnected and the assures that internal
state information (STAT and UIDL) is up-to-date in the object.

If the contact to the server was still present, or could be established,
an M<IO::Socket::INET> object is returned.  Else, C<undef> is returned and
no further actions should be tried on the object.

=error Cannot re-connect reliably to server which doesn't support UIDL.

The connection to the remote POP3 was lost, and cannot be re-established
because the server's protocol implementation lacks the necessary information.

=cut

sub socket(;$)
{   my $self = shift;

    my $socket = $self->_connection;
    return $socket if defined $socket;

    if(exists $self->{MTP_nouidl})
    {   $self->log(ERROR =>
           "Can not re-connect reliably to server which doesn't support UIDL");
        return;
    }

    return unless $socket = $self->login;
    return unless $self->status( $socket );

# Save socket in the object and return it

    $self->{MTP_socket} = $socket;
}

=method send $socket, $data

Send $data to the indicated socket and return the first line read from
that socket.  Logs an error if either writing to or reading from socket failed.

This method does B<not> attempt to reconnect or anything: if reading or
writing the socket fails, something is very definitely wrong.

=error Cannot read POP3 from socket: $!
It is not possible to read the success status of the previously given POP3
command.  Connection lost?

=error Cannot write POP3 to socket: $@
It is not possible to send a protocol command to the POP3 server.  Connection
lost?

=cut

sub send($$)
{   my $self = shift;
    my $socket = shift;
    my $response;
   
    if(eval {print $socket @_})
    {   $response = <$socket>;
        $self->log(ERROR => "Cannot read POP3 from socket: $!")
           unless defined $response;
    }
    else
    {   $self->log(ERROR => "Cannot write POP3 to socket: $@");
    }
    $response;
}

=method sendList $socket, $command
Sends the indicated $command to the specified socket, and retrieves the
response.  It returns a reference to an array with all the lines that
were reveived after the first C<+OK> line and before the end-of-message
delimiter (a single dot on a line).  Returns C<undef>
whenever something has gone wrong.
=cut

sub sendList($$)
{   my $self     = shift;
    my $socket   = shift;
    my $response = $self->send($socket, @_) or return;

    return unless OK($response);

    my @list;
    local $_;
    while(<$socket>)
    {   last if m#^\.\r?\n#s;
        s#^\.##;
	push @list, $_;
    }

    \@list;
}

sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect if $self->{MTP_socket}; # only do if not already done
}

sub OK($;$) { substr(shift || '', 0, 3) eq '+OK' }

sub _connection(;$)
{   my $self = shift;

    my $socket = $self->{MTP_socket};
    defined $socket or return undef;

    # Check if we (still) got a connection
    eval {print $socket "NOOP$CRLF"};
    if($@ || ! <$socket> )
    {   delete $self->{MTP_socket};
        return undef;
    }

    $socket;
}

=method login
Establish a new connection to the POP3 server, using username and password.
 
=error POP3 requires a username and password.
No username and/or no password specified for this POP3 folder, although
these are obligatory parts in the protocol.

=error Cannot connect to $host:$port for POP3: $!
Unsuccesful in connecting to the remote POP3 server.

=error Server at $host:$port does not seem to be talking POP3.
The remote server did not respond to an initial exchange of messages as is
expected by the POP3 protocol.  The server has probably a different
service on the specified port.

=error Could not authenticate using any login method.
No authentication method was explicitly prescribed, so both AUTH and APOP were
tried.  However, both failed.  There are other authentication methods, which
are not defined by the main POP3 RFC rfc1939.  These protocols are not
implemented yet.  Please contribute your implementation.

=error Could not authenticate using '$some' method.

The authenication method to get access to the POP3 server did not result in
a connection.  Maybe you need a different authentication protocol, or your
username with password are invalid.

=cut

sub login(;$)
{   my $self = shift;

# Check if we can make a TCP/IP connection

    local $_; # make sure we don't spoil $_ for the outside world
    my ($interval, $retries, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    unless($username && $password)
    {   $self->log(ERROR => "POP3 requires a username and password.");
        return;
    }

    my $net    = $self->{MTP_ssl} ? 'IO::Socket::SSL' : 'IO::Socket::INET';
    eval "require $net" or die $@;

    my $socket = eval {$net->new("$host:$port")};
    unless($socket)
    {   $self->log(ERROR => "Cannot connect to $host:$port for POP3: $!");
        return;
    }

# Check if it looks like a POP server

    my $connected;
    my $authenticate = $self->{MTP_auth};
    my $welcome = <$socket>;
    unless(OK($welcome))
    {   $self->log(ERROR =>
           "Server at $host:$port does not seem to be talking POP3.");
        return;
    }

# Check APOP login if automatic or APOP specifically requested

    if($authenticate eq 'AUTO' || $authenticate eq 'APOP')
    {   if($welcome =~ m#^\+OK .*(<\d+\.\d+\@[^>]+>)#)
        {   my $md5 = Digest::MD5::md5_hex($1.$password);
            my $response = $self->send($socket, "APOP $username $md5$CRLF");
            $connected = OK($response) if $response;
        }
    }

# Check USER/PASS login if automatic and failed or LOGIN specifically requested

    unless($connected)
    {   if($authenticate eq 'AUTO' || $authenticate eq 'LOGIN')
        {   my $response = $self->send($socket, "USER $username$CRLF")
               or return;

            if(OK($response))
	    {   $response = $self->send($socket, "PASS $password$CRLF")
                   or return;
                $connected = OK($response);
            }
        }
    }

# If we're still not connected now, we have an error

    unless($connected)
    {   $self->log(ERROR => $authenticate eq 'AUTO' ?
         "Could not authenticate using any login method" :
         "Could not authenticate using '$authenticate' method");
        return;
    }

    $socket;
}

#------------------------------------------

=method status $socket
Update the current status of folder on the remote POP3 server.

=error POP3 Could not do a STAT
For some weird reason, the server does not respond to the STAT call.
=cut

sub status($;$)
{   my ($self,$socket) = @_;

# Check if we can do a STAT

    my $stat = $self->send($socket, "STAT$CRLF") or return;
    if($stat =~ m#^\+OK (\d+) (\d+)#)
    {   @$self{qw(MTP_messages MTP_total)} = ($1,$2);
    }
    else
    {   delete $self->{MTP_messages};
        delete $self->{MTP_size};
        $self->log(ERROR => "POP3 Could not do a STAT");
        return;
    }

# Check if we can do a UIDL

    my $uidl = $self->send($socket, "UIDL$CRLF") or return;
    $self->{MTP_nouidl} = undef;
    delete $self->{MTP_uidl2n}; # lose the reverse lookup: UIDL -> number
    if(OK($uidl))
    {   my @n2uidl;
        $n2uidl[$self->{MTP_messages}] = undef; # optimization, sets right size

        local $_;    # protect global $_
        while(<$socket>)
        {   last if substr($_, 0, 1) eq '.';
            s#\r?\n$##;
            $n2uidl[$1] = $2 if m#^(\d+) (.+)#;
        }

        shift @n2uidl; # make message 1 into index 0
        $self->{MTP_n2uidl} = \@n2uidl;
        delete $self->{MTP_n2length};
        delete $self->{MTP_nouidl};
    }

# We can't do UIDL, we need to fake it

    else
    {   my $list = $self->send($socket, "LIST$CRLF") or return;
        my @n2length;
        my @n2uidl;
        if(OK($list))
        {   my $messages = $self->{MTP_messages};
            my ($host, $port) = $self->remoteHost;
            $n2length[$messages] = $n2uidl[$messages] = undef; # optimization
            while(<$socket>)
            {   last if substr($_, 0, 1) eq '.';
                m#^(\d+) (\d+)#;
                $n2length[$1] = $2;
                $n2uidl[$1] = "$host:$port:$1"; # fake UIDL, for id only
            }
            shift @n2length; shift @n2uidl; # make 1st message in index 0
        }
        $self->{MTP_n2length} = \@n2length;
        $self->{MTP_n2uidl} = \@n2uidl;
    }

    my $i = 1;
    my %uidl2n;
    foreach(@{$self->{MTP_n2uidl}})
    {   $uidl2n{$_} = $i++;
    }
    $self->{MTP_uidl2n} = \%uidl2n;
    1;
}

#------------------------------------------

=section Server connection

=method url
Represent this pop3 connection as URL.
=cut

sub url(;$)
{   my ($host, $port, $user, $pwd) = shift->remoteHost;
    "pop3://$user:$pwd\@$host:$port";
}

#------------------------------------------

=section Error handling
=cut

1;
