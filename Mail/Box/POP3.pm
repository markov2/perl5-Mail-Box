
package Mail::Box::POP3;
use base 'Mail::Box::Net';

use strict;
use warnings;

use Mail::Box::POP3::Message;
use Mail::Box::Parser::Perl;

use IO::File;
use File::Spec;
use File::Basename;
use Carp;

=head1 NAME

Mail::Box::POP3 - handle POP3 folders as client

=head1 SYNOPSIS

 use Mail::Box::POP3;
 my $folder = new Mail::Box::POP3 folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

Maintain a folder which has its messages stored on a remote server.  The
communication between the client application and the server is implemented
using the POP3 protocol.  This class uses Mail::Transport::POP3 to
hide the transport of information, and focusses solely on the correct
handling of messages within a POP3 folder.

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

=default server_port  110
=default message_type 'Mail::Box::POP3::Message'

=option  authenticate 'LOGIN'|'APOP'|'AUTO'
=default authenticate 'AUTO'

POP3 can use two methods of authentication: the old LOGIN protocol, which
transmits a username and password in plain text, and the newer APOP
protocol which uses MD5 encryption.  APOP is therefore much better, however
not always supported by the server.  With AUTO, first APOP is tried and
if that fails LOGIN.

=option  pop_client OBJECT
=default pop_client undef

You may want to specify your own pop-client object.  The object
which is passed must extend Mail::Transport::POP3.

=examples

 my $pop = Mail::Box::POP3->new('pop3://user:password@pop.xs4all.nl');

 my $pop = $mgr->open(type => 'pop3', username => 'myname',
    password => 'mypassword', server_name => 'pop.xs4all.nl');

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{trusted}     ||= 0;
    $args->{server_port} ||= 110;

    $self->SUPER::init($args);

    $self->{MBP_client}    = $args->{pop_client}; 
    $self->{MBP_auth}      = $args->{authenticate} || 'AUTO';

    $self;
}


#-------------------------------------------

=head2 Opening folders

=cut

#-------------------------------------------

sub create($@) { undef }         # fails

#-------------------------------------------

sub foundIn(@)
{   my $self = shift;
    unshift @_, 'folder' if @_ % 2;
    my %options = @_;

       (exists $options{type}   && lc $options{type} eq 'pop3')
    || (exists $options{folder} && $options{folder} =~ m/^pop/);
}

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

sub type() {'pop3'}

#-------------------------------------------

=head2 Sub-folders

=cut

#-------------------------------------------

sub listSubFolders(@) { () }     # no

#-------------------------------------------

sub openSubFolder($@) { undef }  # fails

#-------------------------------------------

sub close()
{   my $self = shift;

    my $pop  = $self->popClient;
    $pop->disconnect if defined $pop;

    $self->SUPER::close;
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method popClient

Returns the pop client object.  This does not establish the connection.

=cut

sub popClient()
{   my $self = shift;

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
      );

    $self->log(ERROR => "Cannot create POP3 client ".$self->url)
       unless defined $client;

    $self->{MBP_client} = $client;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $pop   = $self->popClient;
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
 
#-------------------------------------------

=method getHead MESSAGE

Read the header for the specified message from the remote server.

=cut

sub getHead($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->header($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
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
    my $pop   = $self->popClient or return;

    my $uidl  = $message->unique;
    my $lines = $pop->message($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
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
    {   $self->log(WARNING =>
           "Update of $modifications messages ignored for pop3 folder $self.");
    }

    $self;
}

#-------------------------------------------

=head1 IMPLEMENTATION

=head2 How POP3-folders work

=head2 This implementation

=cut

1;
