use strict;
use warnings;

package Mail::Transport;
use base 'Mail::Reporter';

use Carp;
use File::Spec;

=chapter NAME

Mail::Transport - base class for message exchange

=chapter SYNOPSIS

 my $message = Mail::Message->new(...);

 # Some extensions implement sending:
 $message->send;
 $message->send(via => 'sendmail');

 my $sender = M<Mail::Transport::SMTP>->new(...);
 $sender->send($message);

 # Some extensions implement receiving:
 my $receiver = M<Mail::Transport::POP3>->new(...);
 $message = $receiver->receive;

=chapter DESCRIPTION

Objects which extend C<Mail::Transport> implement sending and/or
receiving of messages, using various protocols.

M<Mail::Transport::Send> extends this class, and offers general
functionality for send protocols, like SMTP.  M<Mail::Transport::Receive>
also extends this class, and offers receive method.  Some transport
protocols will implement both sending and receiving.

=chapter METHODS

=cut

my %mailers =
 ( exim     => '::Exim'
 , mail     => '::Mailx'
 , mailx    => '::Mailx'
 , pop      => '::POP3'
 , pop3     => '::POP3'
 , postfix  => '::Sendmail'
 , qmail    => '::Qmail'
 , sendmail => '::Sendmail'
 , smtp     => '::SMTP'
 );

=c_method new %options

=option  hostname HOSTNAME|ARRAY
=default hostname C<'localhost'>
The host on which the server runs.  Some protocols accept an ARRAY
of alternatives for this option.

=option  interval SECONDS
=default interval C<30>
The time between tries to contact the remote server for sending or
receiving a message in SECONDS.  This number must be larger than 0.

=option  password STRING
=default password undef
Some protocols require a password to be given, usually in combination
with a password.

=option  proxy PATH
=default proxy undef
The name of the proxy software (the protocol handler).  This must be
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
=default timeout C<120>
SECONDS till time-out while establishing the connection to a remote server.

=option  username STRING
=default username undef

Some protocols require a user to login.

=option  via CLASS|NAME
=default via C<'sendmail'>
Which CLASS (extending C<Mail::Transport>) will transport the data.
Some predefined NAMEs avoid long class names: C<mail> and C<mailx>
are handled by the M<Mail::Transport::Mailx> module, C<sendmail>
and C<postfix> belong to M<Mail::Transport::Sendmail>, and C<smtp>
is implemented in M<Mail::Transport::SMTP>.  The C<pop> or C<pop3>
protocol implementation can be found in M<Mail::Transport::POP3>.

=option  executable FILENAME
=default executable C<undef>
If you specify an executable, the module does not need to search the
system directories to figure-out where the client lives.  Using this
decreases the flexible usage of your program: moving your program
to other systems may involve changing the path to the executable,
which otherwise would work auto-detect and unmodified.

=warning Avoid program abuse: specify an absolute path for $exec.
Specifying explicit locations for executables of email transfer agents
should only be done with absolute file names, to avoid various pontential
security problems.

=warning Executable $exec does not exist.
The explicitly indicated mail transfer agent does not exists. The normal
settings are used to find the correct location.

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
        or croak "No transport protocol provided";

    $via      = 'Mail::Transport'.$mailers{$via}
       if exists $mailers{$via};

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

    if(my $exec = $args->{executable} || $args->{proxy})
    {   $self->{MT_exec} = $exec;

        $self->log(WARNING => "Avoid program abuse: specify an absolute path for $exec.")
           unless File::Spec->file_name_is_absolute($exec);

        unless(-x $exec)
        {   $self->log(WARNING => "Executable $exec does not exist.");
            return undef;
        }
    }

    $self;
}

#------------------------------------------
=section Server connection

=method remoteHost
Returns the hostname, port number, username and password to be used to
establish the connection to the server for sending or receiving mail.
=cut

sub remoteHost()
{   my $self = shift;
    @$self{ qw/MT_hostname MT_port MT_username MT_password/ };
}

=method retry
Returns the retry interval, retry count, and timeout for the connection.
=cut

sub retry()
{   my $self = shift;
    @$self{ qw/MT_interval MT_retry MT_timeout/ };
}

=method findBinary $name, [@directories]
Look for a binary with the specified $name in the directories which
are defined to be safe.  The list of standard directories is followed
by the optional @directories.  The full pathname is returned.

You may specify M<new(proxy)>, which specifies the absolute name
of the binary to be used.

=cut

my @safe_directories
   = qw(/usr/local/bin /usr/bin /bin /sbin /usr/sbin /usr/lib);

sub findBinary($@)
{   my ($self, $name) = (shift, shift);

    return $self->{MT_exec}
        if exists $self->{MT_exec};

    foreach (@_, @safe_directories)
    {   my $fullname = File::Spec->catfile($_, $name);
        return $fullname if -x $fullname;
    }

    undef;
}

#------------------------------------------
=section Error handling
=cut

1;
