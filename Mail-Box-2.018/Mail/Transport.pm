use strict;
use warnings;

package Mail::Transport;
use base 'Mail::Reporter';

use Carp;
use File::Spec;

our $VERSION = 2.018;

=head1 NAME

Mail::Transport - base class for message exchange

=head1 CLASS HIERARCHY

 Mail::Transport
 is a Mail::Reporter

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

Objects which extend C<Mail::Transport> implement sending and/or
receiving of messages, using various protocols.

L<Mail::Transport::Send> extends this class, and offers general
functionality for send protocols, like SMTP.  L<Mail::Transport::Receive>
also extends this class, and offers receive method.  Some transport
protocols will implement both sending and receiving.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR).

The general methods for C<Mail::Transport> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                       MR warnings
   MR report [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
      findBinary NAME [, DIRECTOR...       remoteHost
   MR inGlobalDestruction                  retry
   MR logPriority LEVEL

=head1 METHODS

=over 4

=cut

my %mailers =
 ( mail     => 'Mail::Transport::Mailx'
 , mailx    => 'Mail::Transport::Mailx'
 , sendmail => 'Mail::Transport::Sendmail'
 , smtp     => 'Mail::Transport::SMTP'
 , pop      => 'Mail::Transport::POP3'
 , pop3     => 'Mail::Transport::POP3'
 );

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN       DEFAULT
 hostname          Mail::Transport    'localhost'
 interval          Mail::Transport    30
 log               Mail::Reporter     'WARNINGS'
 password          Mail::Transport    undef
 port              Mail::Transport    undef
 proxy             Mail::Transport    undef
 retry             Mail::Transport    0
 timeout           Mail::Transport    120
 trace             Mail::Reporter     'WARNINGS'
 username          Mail::Transport    undef
 via               Mail::Transport    'sendmail'

=over 4

=item * hostname =E<gt> HOSTNAME|ARRAY-OF-HOSTNAMES

The host on which the server runs.  Some protocols accept an array
of alternatives for this option.

=item * interval =E<gt> SECONDS

The time between tries to contact the remote server for sending or
receiving a message in SECONDS.  This number must be larger than 0.

=item * password =E<gt> STRING

Some protocols require a password to be given, usually in combination
with a password.

=item * proxy =E<gt> PATH

The name of the proxy software (the mail handler).  This must be
the name (preferable the absolute path) of your mail delivery
software.

=item * port -E<gt> INTEGER

The portnumber behind which the service is hiding on the remote server.

=item * retry =E<gt> NUMBER|undef

The number of retries before the sending will fail.  If C<undef>, the
number of retries is unlimited.

=item * timeout =E<gt> SECONDS

SECONDS till time-out while establishing the connection to a remote server.

=item * username =E<gt> STRING

Some protocols require a user to login.

=item * via =E<gt> CLASS|NAME

Which CLASS (extending C<Mail::Transport>) will transport the data.  Some
predefined NAMEs avoid long class names: C<mail> and C<mailx> are handled
by the C<Mail::Transport::Mailx> module, C<sendmail> belongs to
C<::Sendmail>, and C<smtp> is implemented in C<::SMTP>.  The C<pop> or
C<pop3> protocol implementation can be found in C<::POP3>.

=back

=cut

sub new(@)
{   my $class = shift;
    return $class->SUPER::new(@_) unless $class eq __PACKAGE__;

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

    $self->{MT_username} = $args->{username};
    $self->{MT_password} = $args->{password};
    $self->{MT_interval} = $args->{interval} || 30;
    $self->{MT_retry}    = $args->{retry}    || -1;
    $self->{MT_timeout}  = $args->{timeout}  || 120;
    $self->{MT_proxy}    = $args->{proxy};

    $self;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item remoteHost

Returns the hostname, portnumber, username and password to be used to
establish the connection to the server for sending or receiving mail.

=cut

sub remoteHost()
{   my $self = shift;
    @$self{ qw/MT_hostname MT_port MT_username MT_password/ };
}

#------------------------------------------

=item retry

Returns the retry interval, retry count, and timeout for the connection.

=cut

sub retry()
{   my $self = shift;
    @$self{ qw/MT_interval MT_retry MT_timeout/ };
}

#------------------------------------------

=item findBinary NAME [, DIRECTORIES]

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

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
