
package Mail::Box::POP3;
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::POP3::Message;
use Mail::Box::Parser::Perl;
use Mail::Box::FastScalar;

use File::Spec;
use File::Basename;
use Carp;

=chapter NAME

Mail::Box::POP3 - handle POP3 folders as client

=chapter SYNOPSIS

 use Mail::Box::POP3;
 my $folder = Mail::Box::POP3->new(folder => $ENV{MAIL}, ...);

=chapter DESCRIPTION

Maintain a folder which has its messages stored on a remote server.  The
communication between the client application and the server is implemented
using the POP3 protocol.  This class uses M<Mail::Transport::POP3> to
hide the transport of information, and focusses solely on the correct
handling of messages within a POP3 folder.

=chapter METHODS

=c_method new %options

For authentications, you have three choices: specify a foldername which
resembles an URL, or specify a pop-client object, or separate options
for user, password, pop-server and server-port.

=default folder <not applicable>
=default create <not applicable>

=default server_port  110
=default message_type M<Mail::Box::POP3::Message>

=option  authenticate 'LOGIN'|'APOP'|'AUTO'
=default authenticate C<'AUTO'>
POP3 can use two methods of authentication: the old LOGIN protocol, which
transmits a username and password in plain text, and the newer APOP
protocol which uses MD5 encryption.  APOP is therefore much better, however
not always supported by the server.  With AUTO, first APOP is tried and
if that fails LOGIN.

=option  pop_client OBJECT
=default pop_client undef
You may want to specify your own pop-client object.  The object
which is passed must extend M<Mail::Transport::POP3>.

=examples

 my $url = 'pop3://user:password@pop.xs4all.nl'
 my $pop = Mail::Box::POP3->new($url);

 my $pop = $mgr->open(type => 'pop3',
    username => 'myname', password => 'mypassword',
    server_name => 'pop.xs4all.nl');

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{server_port} ||= 110;
    $args->{folder}      ||= 'inbox';

    $self->SUPER::init($args);

    $self->{MBP_client}    = $args->{pop_client}; 
    $self->{MBP_auth}      = $args->{authenticate} || 'AUTO';

    $self;
}

=ci_method create $folder, %options
It is not possible to create a new folder on a POP3 server.  This method
will always return C<false>.
=cut

sub create($@) { undef }         # fails

sub foundIn(@)
{   my $self = shift;
    unshift @_, 'folder' if @_ % 2;
    my %options = @_;

       (exists $options{type}   && lc $options{type} eq 'pop3')
    || (exists $options{folder} && $options{folder} =~ m/^pop/);
}

=method addMessage $message
It is impossible to write messages to the average POP3 server.  There are
extensions to the protocol which do permit it, however these are not
implemented (yet, patches welcome).

C<undef> is returned, and an error displayed.  However, no complaint is
given when the $message is C<undef> itself.

=error You cannot write a message to a pop server (yet)
Some extensions to the POP3 protocol do permit writing messages to the server,
but the standard protocol only implements retreival.  Feel invited to extend our
implementation with writing.

=cut

sub addMessage($)
{   my ($self, $message) = @_;

    $self->log(ERROR => "You cannot write a message to a pop server (yet)")
       if defined $message;

    undef;
}

=method addMessages $messages
As useless as M<addMessage()>.  The only acceptable call to this method
is without any message.
=cut

sub addMessages(@)
{   my $self = shift;

    # error message described in addMessage()
    $self->log(ERROR => "You cannot write messages to a pop server (yet)")
        if @_;

    ();
}

sub type() {'pop3'}

sub close(@)
{   my $self = shift;

    $self->SUPER::close(@_);

    my $pop = delete $self->{MBP_client};
    $pop->disconnect if defined $pop;

    $self;
}

=method delete %options
It is not possible to delete a POP3 folder remotely: the best we can do
is remove all the messages in it... which is the action implemented here.
A notice is logged about this.

=default recursive <not used>

=warning POP3 folders cannot be deleted.
Each user has only one POP3 folder on a server.  This folder is created and
deleted by the server's administrator only.

=cut

sub delete(@)
{   my $self = shift;
    $self->log(WARNING => "POP3 folders cannot be deleted.");
    undef;
}

=ci_method listSubFolders %options
The standard POP3 protocol does not support sub-folders, so an
empty list will be returned in any case.
=cut

sub listSubFolders(@) { () }     # no

=method openSubFolder %options
It is not possible to open a sub-folder for a POP3 folder, because that
is not supported by the official POP3 protocol. In any case, C<undef>
is returned to indicate a failure.
=cut

sub openSubFolder($@) { undef }  # fails

sub topFolderWithMessages() { 1 }  # Yes: only top folder

=method update
NOT IMPLEMENTED YET
=cut

sub update() {shift->notImplemented}

#-------------------------------------------

=section Internals

=method popClient %options
Returns the pop client object.  This does not establish the connection.

=option  use_ssl BOOLEAN
=default use_ssl <false>

=error Cannot create POP3 client for $name.
The connection to the POP3 server cannot be established.  You may see
more, related, error messages about the failure.
=cut

sub popClient(%)
{   my ($self, %args) = @_;

    return $self->{MBP_client}
        if defined $self->{MBP_client};

    my $auth = $self->{auth};

    require Mail::Transport::POP3;
    my $client  = Mail::Transport::POP3->new
      ( username     => $self->{MBN_username}
      , password     => $self->{MBN_password}
      , hostname     => $self->{MBN_hostname}
      , port         => $self->{MBN_port}
      , authenticate => $self->{MBP_auth}
      , use_ssl      => $args{use_ssl}
      );

    $self->log(ERROR => "Cannot create POP3 client for $self.")
       unless defined $client;

    $self->{MBP_client} = $client;
}

sub readMessages(@)
{   my ($self, %args) = @_;

    my $pop   = $self->popClient or return;
    my @log   = $self->logSettings;
    my $seqnr = 0;

    foreach my $id ($pop->ids)
    {   my $message = $args{message_type}->new
         ( head      => $args{head_delayed_type}->new(@log)
         , unique    => $id
         , folder    => $self
         , seqnr     => $seqnr++
         );

        my $body    = $args{body_delayed_type}->new(@log, message => $message);
        $message->storeBody($body);

        $self->storeMessage($message);
    }

    $self;
}
 
=method getHead $message
Read the header for the specified message from the remote server.
=cut

sub getHead($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->header($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared from POP3 server $self.");
    }

    my $text   = join '', @$lines;
    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => Mail::Box::FastScalar->new(\$text)
     , fix_headers => $self->{MB_fix_headers}
     );

    $self->lazyPermitted(1);

    my $head     = $message->readHead($parser);
    $parser->stop;

    $self->lazyPermitted(0);

    $self->log(PROGRESS => "Loaded head of $uidl.");
    $head;
}

=method getHeadAndBody $message
Read all data for the specified message from the remote server.

=warning Message $uidl on POP3 server $name disappeared.
The server indicated the existence of this message before, however it
has no information about the message anymore.

=error Cannot find head back for $uidl on POP3 server $name.
The server told to have this message, but when asked for its headers, no
single line was returned.  Did the message get destroyed?

=error Cannot read body for $uidl on POP3 server $name.
The message's headers are retrieved from the server, but the body seems
to be lost.  Did the message get destroyed between reading the header
and reading the body?

=cut

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->message($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared from POP3 server $self.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(ERROR => "Cannot find head back for $uidl on POP3 server $self.");
        $parser->stop;
        return undef;
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(ERROR => "Cannot read body for $uidl on POP3 server $self.");
        $parser->stop;
        return undef;
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uidl.");
    ($head, $body);
}

=method writeMessages %options

=error Update of $nr messages ignored for POP3 folder $name.
The standard POP3 implementation does not support writing from client back
to the server.  Therefore, modifications may be lost.

=cut

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->isModified} @{$args->{messages}})
    {   $self->log(WARNING =>
           "Update of $modifications messages ignored for POP3 folder $self.");
    }

    $self;
}

#-------------------------------------------

=chapter DETAILS

=section How POP3 folders work

Rfc1939 defines how POP3 works.  POP3 is a really simple protocol to
receive messages from a server to a user's client.  POP3 is also
really limited: it can only be used to fetch messages, but has not
many ways to limit the amount of network traffic, like the IMAP4
protocol has.

One POP3 account represents only one folder: there is no way of
sub-folders in POP3.  POP3 doesn't support writing (except for
some message status flags).

=section This implementation

The protocol specifics are implemented in M<Mail::Transport::POP3>,
written by Liz Mattijsen.  That module does not use any of the
other POP3 modules available on CPAN for the reason that MailBox
tries to be smarter: it is capable of re-establishing broken POP3
connection when the server supports UIDs.

The implementation has shown to work with many different POP servers.
In the test directory of the distribution, you will find a small
server implementation, which is used to test the client.

=cut


1;
