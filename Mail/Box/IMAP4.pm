
package Mail::Box::IMAP4;
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::IMAP4::Message;
use Mail::Box::Parser::Perl;

use IO::File;
use File::Spec;
use File::Basename;
use Carp;

=head1 NAME

Mail::Box::IMAP4 - handle IMAP4 folders as client

=head1 SYNOPSIS

 use Mail::Box::IMAP4;
 my $folder = new Mail::Box::IMAP4 folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

UNDER DEVELOPMENT: Cannot be used yet!

Maintain a folder which has its messages stored on a remote server.  The
communication between the client application and the server is implemented
using the IMAP4 protocol.  This class uses Mail::Transport::IMAP4 to
hide the transport of information, and focusses solely on the correct
handling of messages within a IMAP4 folder.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

For authentications, you
have three choices: specify a foldername which resembles an URL, or
specify a pop-client object, or separate options for user, password,
pop-server and server-port.

=default server_port  143
=default message_type 'Mail::Box::IMAP4::Message'

=option  authenticate 'KERBEROS_V4'|'GSSAPI'|'SKEY'|'AUTO'
=default authenticate 'AUTO'

IMAP defines various authentications mechanisms.
See Mail::Transport::IMAP4::new(authenticate).

=option  imap_client OBJECT
=default imap_client undef

You may want to specify your own imap-client object.  The object
which is passed must extend Mail::Transport::IMAP4.

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

=head2 Opening folders

=cut

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

=head2 On open folders

=cut

#-------------------------------------------

sub type() {'imap4'}

#-------------------------------------------

=head2 Closing the folder

=cut

#-------------------------------------------

sub close()
{   my $self = shift;

    my $imap  = $self->imapClient;
    $imap->disconnect if defined $imap;

    $self->SUPER::close;
}

#-------------------------------------------

=head2 Sub-folders

=cut

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

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method imapClient

Returns the imap client object: a Mail::Transport::IMAP4 object.
This does not establish the connection.

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

    $self->log(ERROR => "Cannot create IMAP4 client ".$self->url)
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

=cut

sub getHead($)
{   my ($self, $message) = @_;
    my $imap   = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->header($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => IO::ScalarArray->new($lines)
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

=cut

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $imap  = $self->imapClient or return;

    my $uidl  = $message->unique;
    my $lines = $imap->message($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(WARNING => "Cannot find head back for $uidl");
        $parser->stop;
        return undef;
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(ERROR => "Cannot read body for $uidl");
        $parser->stop;
        return undef;
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uidl.");
    ($head, $body);
}

#-------------------------------------------

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->modified} @{$args->{messages}})
    {
    }

    $self;
}

#-------------------------------------------

=head1 IMPLEMENTATION

=head2 How IMAP4 folders work

=head2 This implementation

=cut

1;
