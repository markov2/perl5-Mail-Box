
package Mail::Box::IMAP4;
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::IMAP4::Message;
use Mail::Box::Parser::Perl;
use Mail::Box::FastScalar;

use File::Spec;
use File::Basename;
use Carp;

=chapter NAME

Mail::Box::IMAP4 - handle IMAP4 folders as client

=chapter SYNOPSIS

 use Mail::Box::IMAP4;
 my $folder = new Mail::Box::IMAP4 folder => $ENV{MAIL}, ...;

=chapter DESCRIPTION

UNDER DEVELOPMENT: CANNOT BE USED YET!

Maintain a folder which has its messages stored on a remote server.  The
communication between the client application and the server is implemented
using the IMAP4 protocol.  This class uses Mail::Transport::IMAP4 to
hide the transport of information, and focusses solely on the correct
handling of messages within a IMAP4 folder.

=chapter METHODS

=c_method new OPTIONS

For authentications, you
have three choices: specify a foldername which resembles an URL, or
specify a pop-client object, or separate options for user, password,
pop-server and server-port.

=default server_port  143
=default message_type M<Mail::Box::IMAP4::Message>

=option  authenticate 'KERBEROS_V4'|'GSSAPI'|'SKEY'|'AUTO'
=default authenticate C<'AUTO'>

IMAP defines various authentications mechanisms.
See Mail::Transport::IMAP4::new(authenticate).

=option  imap_client OBJECT
=default imap_client undef

You may want to specify your own imap-client object.  The object
which is passed must extend M<Mail::Transport::IMAP4>.

=option  sub_sep CHARACTER
=default sub_sep <autodetect>

A single character used as sub-folder indicator.  The IMAP protocol is
able to find-out the right separator itself.

=examples

 my $imap = Mail::Box::IMAP4->new('imap4://user:password@imap.xs4all.nl');

 my $imap = $mgr->open(type => 'imap4', username => 'myname',
    password => 'mypassword', server_name => 'pop.xs4all.nl');

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{server_port} ||= 143;

    $self->SUPER::init($args);

    $self->{MBI_client}    = $args->{imap_client}; 
    $self->{MBI_auth}      = $args->{authenticate} || 'AUTO';

    my $imap               = $self->imapClient or return;
    $self->{MBI_subsep}    = $args->{sub_sep}      || $imap->askSubfolderSeparator;

    $self;
}

#-------------------------------------------

sub create($@)
{   my ($class, %args) =  @_;
    $class->log(INTERNAL => "Folder creation for IMAP4 not implemented yet");
    undef;
}

#-------------------------------------------

sub foundIn(@)
{   my $self = shift;
    unshift @_, 'folder' if @_ % 2;
    my %options = @_;

       (exists $options{type}   && $options{type}   =~ m/^imap/i)
    || (exists $options{folder} && $options{folder} =~ m/^imap/);
}

#-------------------------------------------

sub type() {'imap4'}

#-------------------------------------------

sub close()
{   my $self = shift;

    my $imap  = $self->imapClient;
    $imap->disconnect if defined $imap;

    $self->SUPER::close;
}

#-------------------------------------------

sub listSubFolders(@)
{   my ($thing, %args) = @_;

    my $self
     = ref $thing ? $thing                # instance method
     :              $thing->new(%args);   # class method

    return () unless defined $self;

    my $imap = $self->imapClient
        or return ();

    my $name      = $imap->folderName;
    $name         = "" if $name eq '/';

    $self->askSubfoldersOf("$name$self->{MBI_subsep}");
}

#-------------------------------------------

sub nameOfSubfolder($)
{   my ($self, $name) = @_;
    "$self" . $self->{MBI_subsep} . $name;
}

#-------------------------------------------

=section Internals

=method imapClient

Returns the IMAP client object: a M<Mail::Transport::IMAP4> object.
This does not establish the connection.

=error Cannot create IMAP4 client $url.

Connecting to the specified IMAP4 server failed.  A message about the reason
is produced as well.

=cut

sub imapClient()
{   my $self = shift;

    return $self->{MBI_client}
        if defined $self->{MBI_client};

    my $auth = $self->{auth};

    require Mail::Transport::IMAP4;
    my $client  = Mail::Transport::IMAP4->new
      ( username     => $self->{MBN_username}
      , password     => $self->{MBN_password}
      , hostname     => $self->{MBN_hostname}
      , port         => $self->{MBN_port}
      , authenticate => $self->{MBI_auth}
      );

    $self->log(ERROR => "Cannot create IMAP4 client ".$self->url.'.')
       unless defined $client;

    $self->{MBI_client} = $client;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $imap   = $self->imapClient;
    my @log   = $self->logSettings;
    my $seqnr = 0;

#### Things must be changed here...
    foreach my $id ($imap->ids)
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
 
#-------------------------------------------

=method getHead MESSAGE

Read the header for the specified message from the remote server.
C<undef> is returned in case the message disappeared.

=warning Message $uidl disappeared from $folder.

Trying to get the specific message from the server, but it appears to be
gone.

=cut

sub getHead($)
{   my ($self, $message) = @_;
    my $imap   = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->header($uidl);

    unless(defined $lines)
    {   $self->log(WARNING => "Message $uidl disappeared from $self.");
        return;
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => Mail::Box::FastScalar->new(join '', @$lines)
     );

    $self->lazyPermitted(1);

    my $head     = $message->readHead($parser);
    $parser->stop;

    $self->lazyPermitted(0);

    $self->log(PROGRESS => "Loaded head of $uidl.");
    $head;
}

#-------------------------------------------

=method getHeadAndBody MESSAGE

Read all data for the specified message from the remote server.
Return head and body of the mesasge as list, or an empty list
if the MESSAGE disappeared from the server.

=warning Message $uidl disappeared from $folder.

Trying to get the specific message from the server, but it appears to be
gone.

=warning Cannot find head back for $uidl in $folder.

The header was read before, but now seems empty: the IMAP4 server does
not produce the header lines anymore.

=warning Cannot read body for $uidl in $folder.

The header of the message was retreived from the IMAP4 server, but the
body is not read, for an unknown reason.

=cut

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $imap  = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->message($uidl);

    unless(defined $lines)
    {   $self->log(WARNING  => "Message $uidl disappeared from $self.");
        return ();
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => Mail::Box::FastScalar->new(join '', @$lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(WARNING => "Cannot find head back for $uidl in $self.");
        $parser->stop;
        return ();
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(WARNING => "Cannot read body for $uidl in $self.");
        $parser->stop;
        return ();
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uidl.");
    ($head, $body);
}

#-------------------------------------------

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->isModified} @{$args->{messages}})
    {
    }

    $self;
}

#-------------------------------------------

=section Error handling

=chapter DETAILS

=section How IMAP4 folders work

=cut

1;
