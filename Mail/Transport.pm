use strict;
use warnings;

package Mail::Transport;
use base 'Mail::Reporter';

use Carp;
use File::Spec;

=head1 NAME

Mail::Transport - base class for message exchange

=head1 SYNOPSIS

 my $message = Mail::Message->new(...);

 # Some extensions implement sending:
 $message->send;
 $message->send(via => 'sendmail');

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

 # Some extensions implement receiving:
 my $receiver = Mail::Transport::POP3->new(...);
 $message = $receiver->receive;

=head1 DESCRIPTION

Objects which extend Mail::Transport implement sending and/or
receiving of messages, using various protocols.

Mail::Transport::Send extends this class, and offers general
functionality for send protocols, like SMTP.  Mail::Transport::Receive
also extends this class, and offers receive method.  Some transport
protocols will implement both sending and receiving.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

my %mailers =
 ( mail     => 'Mail::Transport::Mailx'
 , mailx    => 'Mail::Transport::Mailx'
 , sendmail => 'Mail::Transport::Sendmail'
 , smtp     => 'Mail::Transport::SMTP'
 , pop      => 'Mail::Transport::POP3'
 , pop3     => 'Mail::Transport::POP3'
 );

#------------------------------------------

=method new OPTIONS

=option  hostname HOSTNAME|ARRAY-OF-HOSTNAMES
=default hostname 'localhost'

The host on which the server runs.  Some protocols accept an array
of alternatives for this option.

=option  interval SECONDS
=default interval 30

The time between tries to contact the remote server for sending or
receiving a message in SECONDS.  This number must be larger than 0.

=option  password STRING
=default password undef

Some protocols require a password to be given, usually in combination
with a password.

=option  proxy PATH
=default proxy undef

The name of the proxy software (the mail handler).  This must be
the name (preferable the absolute path) of your mail delivery
software.

=option  port INTEGER
=default port undef

The port number behind which the service is hiding on the remote server.

=option  retry NUMBER|undef
=default retry <false>

The number of retries before the sending will fail.  If C<undef>, the
number of retries is unlimited.

=option  timeout SECONDS
=default timeout 120

SECONDS till time-out while establishing the connection to a remote server.

=option  username STRING
=default username undef

Some protocols require a user to login.

=option  via CLASS|NAME
=default via 'sendmail'

Which CLASS (extending Mail::Transport) will transport the data.  Some
predefined NAMEs avoid long class names: C<mail> and C<mailx> are handled
by the Mail::Transport::Mailx module, C<sendmail> belongs to
C<::Sendmail>, and C<smtp> is implemented in C<::SMTP>.  The C<pop> or
C<pop3> protocol implementation can be found in C<::POP3>.

=cut

sub new(@)
{   my $class = shift;

    return $class->SUPER::new(@_)
        unless $class eq __PACKAGE__ || $class eq "Mail::Transport::Send";

    #
    # auto restart by creating the right transporter.
    #

    my %args  = @_;
    my $via   = lc($args{via} || '')
        or croak "No transport protocol provided.\n";

    $via      = $mailers{$via} if exists $mailers{$via};

    eval "require $via";
    return undef if $@;

    $via->new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MT_hostname}
       = defined $args->{hostname} ? $args->{hostname} : 'localhost';

    $self->{MT_port}     = $args->{port};
    $self->{MT_username} = $args->{username};
    $self->{MT_password} = $args->{password};
    $self->{MT_interval} = $args->{interval} || 30;
    $self->{MT_retry}    = $args->{retry}    || -1;
    $self->{MT_timeout}  = $args->{timeout}  || 120;
    $self->{MT_proxy}    = $args->{proxy};

    $self;
}

#------------------------------------------

=head2 Server Connection

=cut

#------------------------------------------

=method remoteHost

Returns the hostname, port number, username and password to be used to
establish the connection to the server for sending or receiving mail.

=cut

sub remoteHost()
{   my $self = shift;
    @$self{ qw/MT_hostname MT_port MT_username MT_password/ };
}

#------------------------------------------

=method retry

Returns the retry interval, retry count, and timeout for the connection.

=cut

sub retry()
{   my $self = shift;
    @$self{ qw/MT_interval MT_retry MT_timeout/ };
}

#------------------------------------------

=method findBinary NAME [, DIRECTORIES]

Look for a binary with the specified NAME in the directories which
are defined to be safe.  The list of standard directories is followed
by the optional DIRECTORIES.  The full pathname is returned.

You may specify a C<proxy> option, which specifies the absolute name
of the binary to be used.

=cut

my @safe_directories = qw(/usr/local/bin /usr/bin /bin
   /sbin /usr/sbin /usr/lib);

sub findBinary($@)
{   my ($self, $name) = (shift, shift);

    foreach (@safe_directories, @_)
    {   my $fullname = File::Spec->catfile($_, $name);
        return $fullname if -x $fullname;
    }

    undef;
}

#------------------------------------------

1;
