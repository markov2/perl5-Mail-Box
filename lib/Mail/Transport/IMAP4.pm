
use strict;
use warnings;

package Mail::Transport::IMAP4;
use base 'Mail::Transport::Receive';

my $CRLF = $^O eq 'MSWin32' ? "\n" : "\015\012";

=chapter NAME

Mail::Transport::IMAP4 - proxy to Mail::IMAPClient

=chapter SYNOPSIS

 my $imap = Mail::Transport::IMAP4->new(...);
 my $message = $imap->receive($id);
 $imap->send($message);

=chapter DESCRIPTION

****** UNDER DEVELOPMENT *****, cannot be used (yet)


The IMAP4 protocol is quite complicated: it is feature rich and allows
verious asynchronous actions.  The main document describing IMAP is
rfc3501 (which obsoleted the original specification of protocol 4r1
in rfc2060 in March 2003).

This package, as part of Mail::Box, does not implement the actual
protocol itself but uses M<Mail::IMAPClient> to do the work.  The task
for this package is to hide as many differences between that module's
interface and the common M<Mail::Box> folder types.  Multiple
M<Mail::Box::IMAP4> folders can share one M<Mail::Transport::IMAP4>
connection.

=chapter METHODS

=c_method new OPTIONS

Create the IMAP connection to the server.  IMAP servers can handle
multiple folders for a single user, which means that connections
may get shared.  This is sharing is hidden for the user.

=default port 143
=default via  C<'imap'>

=option  authenticate 'PLAIN'|'CRAM-MD5'|'NTLM'|'AUTO'|CODE
=default authenticate C<'AUTO'>

Authenthication method.  C<AUTO> will try all known methods.
The NTLM authentication requires M<Authen::NTLM> to be installed.  If this
module is not installed, it will be skipped by AUTO.

You can also specify your own mechan$^O eq 'MSWin32' ? "\n" : ism as CODE reference.  The
M<Mail::IMAPClient> documentation refers to this code as I<Authcallback>.
In case you have your own implementation, please consider to contribute
it to Mail::Box.

=error module Authen::NTLM is not installed
You try to establish an IMAP4 connection which explicitly uses NTLM
authentication, but the optional M<Authen::NTLM>, which implements this is
not installed on your system.

=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{via}    = 'imap4';
    $args->{port} ||= 143;

    $self->SUPER::init($args) or return;

    my $auth = $self->{MTI_auth} = $args->{authenticate} || 'AUTO';
    eval "require Authen::NTML";
    $self->log(ERROR => 'module Authen::NTLM is not installed')
       if $auth eq 'NTLM' && $@;

    return unless $self->socket;   # establish connection

    $self;
}

#------------------------------------------

=method url

Represent this imap4 connection as URL.

=cut

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    my $name = $self->folderName;
    "imap4://$user:$pwd\@$host:$port$name";
}

#------------------------------------------

=section Exchanging Information

=method ids

Returns a list (in list context) or a reference to a list (in scalar context)
of all ID's which are known by the server on this moment.

=cut

sub ids(;@)
{   my $self = shift;
    return unless $self->socket;
    wantarray ? @{$self->{MTI_n2uidl}} : $self->{MTI_n2uidl};
}

#------------------------------------------

=method messages

Returns (in scalar context only) the number of messages that are known
to exist in the mailbox.

=error Cannot get the messages of imap4 via messages()

It is not possible to retreive all messages on a remote IMAP4 folder
at once: each shall be taken separately.  The IMAP4 folder will hide this
for you.

=cut

sub messages()
{   my $self = shift;

    $self->log(ERROR =>"Cannot get the messages of imap4 via messages()."), return ()
       if wantarray;

    $self->{MTI_messages};
}

#------------------------------------------

=method folderSize

Returns the total number of octets used by the mailbox on the remote server.

=cut

sub folderSize() { shift->{MTI_total} }

#------------------------------------------

=method header ID, [BODYLINES]

Returns a reference to an array which contains the header of the message
with the specified ID.  C<undef> is returned if something has gone wrong.

The optional integer BODYLINES specifies the number of lines from the body
which should be added, by default none.

=example

 my $ref_lines = $imap4->header($uidl);
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

#------------------------------------------

=method message ID

Returns a reference to an array which contains the lines of the
message with the specified ID.  Returns C<undef> if something has gone
wrong.

=example

 my $ref_lines = $imap->message($uidl);
 print @$ref_lines;

=cut

sub message($;$)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $socket  = $self->socket      or return;
    my $n       = $self->id2n($uidl) or return;
    my $message = $self->sendList($socket, "RETR $n$CRLF");

    return unless $message;

    # Some IMAP4 servers add a trailing empty line
    pop @$message if @$message && $message->[-1] =~ m/^[\012\015]*$/;

    return if exists $self->{MTI_nouidl};

    $self->{MTI_fetched}{$uidl} = undef; # mark this ID as fetched
    $message;
}

#------------------------------------------

=method messageSize ID

Returns the size of the message which is indicated by the ID, in octets.
If the message has been deleted on the remote server, this will return
C<undef>.

=cut

sub messageSize($)
{   my ($self, $uidl) = @_;
    return unless $uidl;

    my $list;
    unless($list = $self->{MTI_n2length})
    {   my $socket = $self->socket or return;
        my $raw = $self->sendList($socket, "LIST$CRLF") or return;
        my @n2length;
        foreach (@$raw)
        {   m#^(\d+) (\d+)#;
            $n2length[$1] = $2;
        }   
        $self->{MTI_n2length} = $list = \@n2length;
    }

    my $n = $self->id2n($uidl) or return;
    $list->[$n];
}

#------------------------------------------

=method deleted BOOLEAN, ID's

Either mark the specified message(s) to be deleted on the remote server or
unmark them for deletion (if the first parameter is false).  Deletion of
messages will take place B<only> when the connection is specifically
disconnected or the last reference to the object goes out of scope.

=cut

sub deleted($@)
{   my $dele = shift->{MTI_dele} ||= {};
    (shift) ? @$dele{ @_ } = () : delete @$dele{ @_ };
}


#------------------------------------------

=method deleteFetched

Mark all messages that have been fetched with message() for deletion.  See
fetched().

=cut

sub deleteFetched()
{   my $self = shift;
    $self->deleted(1, keys %{$self->{MTI_fetched}});
}

#------------------------------------------

=method disconnect

Break contact with the server, if that (still) exists.  Returns true if
successful.  Please note that even if the disconnect was not successful,
all knowledge of messages etc. will be removed from the object: the object
basically has reverted to the state in which it was before anything was done
with the mail box.

=cut

sub disconnect()
{   my $self = shift;
}

#------------------------------------------

=method fetched

Returns a reference to a list of ID's that have been fetched using the
message() method.  This can be used to update a database of messages that
were fetched (but maybe not yet deleted) from the mailbox.

Please note that if the IMAP4 server did not support the UIDL command, this
method will always return undef because it is not possibly to reliably
identify messages between sessions (other than looking at the contents of
the messages themselves).

See also deleteFetched().

=cut

sub fetched(;$)
{   my $self = shift;
    return if exists $self->{MTI_nouidl};
    $self->{MTI_fetched};
}

#------------------------------------------

=method id2n ID

Translates the unique ID of a message into a sequence number which
represents the message as long a this connection to the IMAP4 server
exists.  When the message has been deleted for some reason, C<undef>
is returned.

=cut

sub id2n($;$) { shift->{MTI_uidl2n}{shift()} }

#------------------------------------------

=section Protocol [internals]

The follow methods handle protocol internals, and should not be used
by a normal user of this class.

=cut

#------------------------------------------

=method socket

Returns a connection to the IMAP4 server.  If there was no connection yet,
it will be created transparently.  If the connection with the IMAP4 server
was lost, it will be reconnected and the assures that internal
state information (STAT and UID) is up-to-date in the object.

If the contact to the server was still present, or could be established,
an M<IO::Socket::INET> object is returned.  Else, C<undef> is returned and
no further actions should be tried on the object.

=error Cannot re-connect reliably to server which doesn't support UID.

The connection to the remote IMAP4 was lost, and cannot be re-established
because the server's protocol implementation lacks the necessary information.

=cut

sub socket(;$)
{   my $self = shift;

    my $socket = $self->_connection;
    return $socket if $socket;

    unless(exists $self->{MTI_nouidl})
    {   $self->log(ERROR =>
           "Can not re-connect reliably to server which doesn't support UIDL");
        return;
    }

    return unless $socket = $self->login;
    return unless $self->_status( $socket );

# Save socket in the object and return it

    $self->{MTI_socket} = $socket;
}

#------------------------------------------

=method send SOCKET, data

Send data to the indicated socket and return the first line read from
that socket.  Logs an error if either writing to or reading from socket failed.

This method does B<not> attempt to reconnect or anything: if reading or
writing the socket fails, something is very definitely wrong.

=error Cannot read IMAP4 from socket: $!

It is not possible to read the success status of the previously given IMAP4
command.  Connection lost?

=error Cannot write IMAP4 to socket: $@

It is not possible to send a protocol command to the IMAP4 server.  Connection
lost?

=cut

sub send($$)
{   my $self = shift;
    my $socket = shift;
    my $response;
   
    if(eval {print $socket @_})
    {   $response = <$socket>;
        $self->log(ERROR => "Cannot read IMAP4 from socket: $!")
	   unless defined $response;
    }
    else
    {   $self->log(ERROR => "Cannot write IMAP4 to socket: $@");
    }
    $response;
}

#------------------------------------------

=method sendList SOCKET, COMMAND

Sends the indicated COMMAND to the specified socket, and retrieves the
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
    local $_; # make sure we don't spoil it for the outside world
    while(<$socket>)
    {   last if m#^\.\r?$CRLF#s;
        s#^\.##;
	push @list, $_;
    }

    \@list;
}

#------------------------------------------

sub OK($;$) { substr(shift || '', 0, 3) eq '+OK' }

#------------------------------------------

sub _connection(;$)
{   my $self = shift;
   my $socket = $self->{MTI_socket} or return undef;

    # Check if we (still) got a connection
    eval {print $socket "NOOP$CRLF"};
    if($@ || ! <$socket> )
    {   delete $self->{MTP_socket};
        return undef;
    }

    $socket;
}

#------------------------------------------

sub _reconnectok
{   my $self = shift;

# See if we are allowed to reconnect

    0;
}

#------------------------------------------

=method login

Establish a new connection to the IMAP4 server, using username and password.

=error IMAP4 requires a username and password
=error Cannot connect to $host:$port for IMAP4: $!

=cut

sub login(;$)
{   my $self = shift;

# Check if we can make a TCP/IP connection

    local $_; # make sure we don't spoil it for the outside world
    my ($interval, $retries, $timeout) = $self->retry;
    my ($host, $port, $username, $password) = $self->remoteHost;
    unless($username and $password)
    {   $self->log(ERROR => "IMAP4 requires a username and password");
        return;
    }

    my $socket = eval {IO::Socket::INET->new("$host:$port")};
    unless($socket)
    {   $self->log(ERROR => "Cannot connect to $host:$port for IMAP4: $!");
        return;
    }

# Check if it looks like a POP server

    my $connected;
    my $authenticate = $self->{MTI_auth};
    my $welcome = <$socket>;
    unless(OK($welcome))
    {   $self->log(ERROR =>
           "Server at $host:$port does not seem to be talking IMAP4");
        return;
    }

# Check APOP login if automatic or APOP specifically requested

    if($authenticate eq 'AUTO' or $authenticate eq 'APOP')
    {   if($welcome =~ m#^\+OK (<\d+\.\d+\@[^>]+>)#)
        {   my $md5 = Digest::MD5::md5_hex($1.$password);
            my $response = $self->send($socket, "APOP $username $md5$CRLF")
	     or return;
            $connected = OK($response);
        }
    }

# Check USER/PASS login if automatic and failed or LOGIN specifically requested

    unless($connected)
    {   if($authenticate eq 'AUTO' or $authenticate eq 'LOGIN')
        {   my $response = $self->send($socket, "USER $username$CRLF") or return;
            if(OK($response))
	    {   $response = $self->send($socket, "PASS $password$CRLF") or return;
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

sub _status($;$)
{   my ($self,$socket) = @_;

# Check if we can do a STAT

    my $stat = $self->send($socket, "STAT$CRLF") or return;
    if($stat =~ m#^\+OK (\d+) (\d+)#)
    {   @$self{qw(MTI_messages MTI_total)} = ($1,$2);
    }
    else
    {   delete $self->{MTI_messages};
        delete $self->{MTI_size};
        $self->log(ERROR => "Could not do a STAT");
        return;
    }

# Check if we can do a UIDL

    my $uidl = $self->send($socket, "UIDL$CRLF") or return;
    $self->{MTI_nouidl} = undef;
    delete $self->{MTI_uidl2n}; # lose the reverse lookup: UIDL -> number
    if(OK($uidl))
    {   my @n2uidl;
        $n2uidl[$self->{MTI_messages}] = undef; # optimization, sets right size
        while(<$socket>)
        {   last if substr($_, 0, 1) eq '.';
            s#\r?$CRLF$##; m#^(\d+) (.+)#;
            $n2uidl[$1] = $2;
        }
        shift @n2uidl; # make message 1 into index 0
        $self->{MTI_n2uidl} = \@n2uidl;
        delete $self->{MTI_n2length};
        delete $self->{MTI_nouidl};
    }

# We can't do UIDL, we need to fake it

    else
    {   my $list = $self->send($socket, "LIST$CRLF") or return;
        my @n2length;
        my @n2uidl;
        if(OK($list))
        {   my $messages = $self->{MTI_messages};
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
        $self->{MTI_n2length} = \@n2length;
        $self->{MTI_n2uidl} = \@n2uidl;
    }

    my $i = 1;
    my %uidl2n;
    foreach(@{$self->{MTI_n2uidl}})
    {   $uidl2n{$_} = $i++;
    }
    $self->{MTI_uidl2n} = \%uidl2n;
    1;
}

#------------------------------------------

=method askSubfolderSeparator

Returns the separator which is used on the server side to indicate
sub-folders.

=cut

sub askSubfolderSeparator()
{   my $self = shift;

    # $self->send(A000 LIST "" "")
    # receives:  * LIST (\Noselect) "/" ""
    #                                ^ $SEP
    # return $SEP    [exactly one character)

    $self->notImplemented;
}

#------------------------------------------

=method askSubfoldersOf NAME

Returns a list of subfolders for this server.

=cut

sub askSubfoldersOf($)
{   my ($self, $name) = @_;
    
    # $imap->send(LIST "$name" %)
    # receives multiple lines
    #     * LIST (.*?) NAME
    # return list of NAMEs

    $self->notImplemented;
}

#------------------------------------------

=method getFlags ID

Returns the values of all flags which are related to the message with the
specified ID.  These flags are translated into the names which are
standard for the Mail::Box suite

=cut

# Explanation in Mail::Box::IMAP::Message chapter DETAILS
my %systemflags =
 ( '\Seen'     => 'seen'
 , '\Answered' => 'replied'
 , '\Flagged'  => 'flagged'
 , '\Deleted'  => 'deleted'
 , '\Draft'    => 'draft'
 , '\Recent'   => 'old'       #  NOT old
 );

sub getLabel($$)
{   my ($self, $id, $label) = @_;

    $self->notImplemented;
}

#------------------------------------------

=method setFlags ID, LABEL, VALUE, [LABEL, VALUE], ...

=cut

sub setFlags($@)
{   my ($self, $id) = (shift, shift);
    my @flags = @_;  # etc

    $self->notImplemented;
}

#------------------------------------------

=section Error handling

=section Cleanup

=method DESTROY

The connection is cleanly terminated when the program is cleanly
terminated.

=cut

sub DESTROY()
{   my $self = shift;
    $self->SUPER::DESTROY;
    $self->disconnect if $self->{MTI_socket}; # only do if not already done
}

1;
