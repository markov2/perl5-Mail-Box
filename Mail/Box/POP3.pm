
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

WARNING: THE POP3 IMPLEMENTATION IS UNDER CONSTRUCTION: IT WILL *NOT*
WORK AT ALL!!!!

This documentation describes how POP3 mailboxes work, and what you
can do with the POP3 folder object C<Mail::Box::POP3>.
Please read C<Mail::Box-Overview> and C<Mail::Box> first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.

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

=option  authenticate 'LOGIN'|'APOP'
=default authenticate 'LOGIN'

POP3 can use two methods of authentication: the old LOGIN protocol, which
transmits a username and password in plain text, and the newer APOP
protocol which uses MD5 encryption.  APOP is therefore much better, however
not always supported by the server.

=option  pop_client OBJECT
=default pop_client undef

You may want to specify your own pop-client object.  The object
which is passed must extend C<Mail::Transport::POP3>.

=examples

 my $pop = Mail::Box::POP3->new('pop3://user:password@pop.xs4all.nl');

 my $pop = $mgr->open(type => 'pop3', username => 'myname',
    password => 'mypassword', server_name => 'pop.xs4all.nl');

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{trusted}     ||= 0;
    $args->{server_port} ||= 110;

    my $client             = $args->{pop_client};
    $args->{foldername}  ||= defined $client ? $client->url : undef;

    $self->SUPER::init($args);

    $self->{MBP_client}    = $client;
    $self->{MBP_auth}      = $args->{authenticate} || 'LOGIN';

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

=head2 Sub-folders

=cut

#-------------------------------------------

sub listSubFolders(@) { () }     # no

#-------------------------------------------

sub openSubFolder($@) { undef }  # fails

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method popClient

Returns the pop client object.  This does not establish the connection.

=cut

sub popClient()
{   my $self = shift;

    return $self->{MBP_client} if exists $self->{MBP_client};

    my $auth = $self->{auth};

    require Mail::Transport::POP3;
    my $client  = Mail::Transport::POP3->new
     ( username     => $self->{MBN_username}
     , password     => $self->{MBN_password}
     , hostname     => $self->{MBN_hostname}
     , port         => $self->{MBN_port}
     , authenticate => $self->{MBP_auth}
     );

    $self->{MBP_client} = $client;
}

#-------------------------------------------

sub readMessages(@)
{   my ($self, %args) = @_;

    my $directory = $self->directory;
    return unless -d $directory;

    my @msgnrs = $self->readMessageFilenames($directory);

    my @log    = $self->logSettings;
    foreach my $msgnr (@msgnrs)
    {
        my $msgfile = File::Spec->catfile($directory, $msgnr);

        my $head;
        $head     ||= $args{head_delayed_type}->new(@log);

        my $message = $args{message_type}->new
         ( head      => $head
         , filename  => $msgfile
         , folder    => $self
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

    my $uidl  = $message->uidl;
    my $lines = $pop->top($uidl, 0);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head     = $self->readHead($parser);
    $parser->stop;

    $self->log(PROGRESS => "Loaded head $uidl.");
    $head;
}

#-------------------------------------------

=method getHeadAndBody MESSAGE

Read all data for the specified message from the remote server.

=cut

sub getHeadAndBody($)
{   my ($self, $message) = @_;
    my $pop   = $self->popClient or return;

    my $uidl  = $message->uidl;
    my $lines = $pop->top($uidl);

    unless(defined $lines)
    {   $lines = [];
        $self->log(WARNING  => "Message $uidl disappeared.");
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$pop"
     , file      => IO::ScalarArray->new($lines)
     );

    my $head     = $message->readHead($parser);
    my $body     = $message->readBody($parser, $head);

    $parser->stop;

    $self->log(PROGRESS => "Loaded head $uidl.");
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
