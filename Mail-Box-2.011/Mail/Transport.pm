use strict;
use warnings;

package Mail::Transport;
use base 'Mail::Reporter';

use Carp;
use File::Spec;
use Errno 'EAGAIN';

our $VERSION = 2.011;

=head1 NAME

Mail::Transport - base class for message transmission

=head1 CLASS HIERARCHY

 Mail::Transport
 is a Mail::Reporter

=head1 SYNOPSIS

 my $message = Mail::Message->new(...);
 $message->send;
 $message->send(via => 'sendmail');

 my $sender = Mail::Transport::SMTP->new(...);
 $sender->send($message);

=head1 DESCRIPTION

Organize sending of C<Mail::Message> objects to the destinations as
specified in the header.  The C<Mail::Transport> module is capable to
autodetect which of the following modules work on your system:

=over 4

=item * C<Mail::Transport::Sendmail>

Use sendmail to process and deliver the mail.  This requires the
C<sendmail> program to be installed on your system.

=item * C<Mail::Transport::Qmail>

Use C<qmail-inject> to distribute the message.

=item * C<Mail::Transport::SMTP>

In this case, Perl is handling mail transport on its own.  This is less
desired but more portable than sending with sendmail or qmail.

The advantage is that this sender is environment independent, and easier to
configure.  However, there is no daemon involved which means that your
program will wait until the message is delivered, and the message is
lost when your program is interrupted during delivery (which may
take hours to complete).

=item * C<Mail::Transport::Mailx>

Use the external C<mail>, C<mailx>, or C<Mail> programs to send the
message.  Usually, the result is poor, because some versions of these
programs do not support MIME headers.

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR).

The general methods for C<Mail::Transport> objects:

   MR errors                            MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]               send MESSAGE, OPTIONS
      new OPTIONS                       MR trace [LEVEL]
   MR report [LEVEL]                       trySend MESSAGE, OPTIONS

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
      findBinary NAME [, DIRECTOR...    MR notImplemented
   MR inGlobalDestruction                  putContent MESSAGE, FILEHAN...

=head1 METHODS

=over 4

=cut

my %mailers =
 ( mail     => 'Mail::Transport::Mailx'
 , mailx    => 'Mail::Transport::Mailx'
 , sendmail => 'Mail::Transport::Sendmail'
 , smtp     => 'Mail::Transport::SMTP'
 );

#------------------------------------------

=item new OPTIONS

 OPTION            DESCRIBED IN       DEFAULT
 log               Mail::Reporter     'WARNINGS'
 trace             Mail::Reporter     'WARNINGS'
 via               Mail::Transport    'smtp'
 proxy             Mail::Transport    undef

=over 4

=item * proxy =E<gt> PATH

The name of the proxy software (the mail handler).  This must be
the name (preferable the absolute path) of your mail delivery
software.

=item * via =E<gt> CLASS|NAME

Which CLASS (extending C<Mail::Transport>) will transport the data.  Some
predefined NAMEs avoid long class names: C<mail> and C<mailx> are handled
by the C<Mail::Transport::Mailx> module, C<sendmail> belongs to
C<::Sendmail>, and C<smtp> is implemented in C<::SMTP>.

=back

=cut

sub new(@)
{   my $class = shift;
    return $class->SUPER::new(@_) unless $class eq __PACKAGE__;

    my %args  = @_;
    my $via   = lc($args{via} || 'sendmail');
    $via      = $mailers{$via} if exists $mailers{$via};

    eval "require $via";
warn $@ if $@;
    return undef if $@;

    $via->new(@_);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    $self;
}

#------------------------------------------

=item send MESSAGE, OPTIONS

Transmit the MESSAGE, which may be anything what can be coerced into a
C<Mail::Message>, so including C<Mail::Internet> and C<MIME::Entity>
messages.  It returns true when the transmission was succesfully completed.

Some extensions to C<Mail::Transport> may offer OPTIONS, but at least the
following are supported:

 OPTIONS      DESCRIBED IN              DEFAULT
 interval     Mail::Transport           30
 retry        Mail::Transport           undef

=over 4

=item * interval =E<gt> SECONDS

Retry to send the message every so many SECONDS, until transmission is
successful or the number of retries is reached.  The number must be
larger than 0.

=item * retry =E<gt> NUMBER|undef

The number of retries before the sending will fail.  If C<undef>, the
number of retries is unlimited.

=back

=cut

sub send($@)
{   my ($self, $message) = (shift, shift);

    unless($message->isa('Mail::Message'))  # avoid rebless.
    {   $message = Mail::Message->coerce($message);
        confess "Unable to coerce object into Mail::Message."
            unless defined $message;
    }

    return 1 if $self->trySend($message);
    return 0 unless $?==EAGAIN;

    my %args     = @_;
    my $interval = $args{interval} || 30;
    my $retry    = $args{retry}    || -1;
    while($retry!=0)
    {   sleep $interval;
        return 1 if $self->trySend($message);
        return 0 unless $?==EAGAIN;
        $retry--;
    }

    0;
}

#------------------------------------------

=item trySend MESSAGE, OPTIONS

Try to send the message. This will return true if successful, and
false in case some problems where detected.  The C<$?> contains
the exit status of the command which was started.

=cut

sub trySend($@)
{   my $self = shift;
    croak "Transporters of type ",ref $self, " cannot send.";
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item putContent MESSAGE, FILEHANDLE, OPTIONS

Print the content of the MESSAGE to the FILEHANDLE.

 OPTIONS           DESCRIBED IN         DEFAULT
 body_only         Mail::Transport      <false>
 undisclosed       Mail::Transport      <false>

=over 4

=item * body_only =E<gt> BOOLEAN

Print only the body of the message, not the whole.

=item * undisclosed =E<gt> BOOLEAN

Do not print the C<Bcc> and C<Resent-Bcc> lines.  Default false, which
means that they are printed.

=back

=cut

sub putContent($$@)
{   my ($self, $message, $fh, %args) = @_;

       if($args{body_only})   { $message->body->print($fh) }
    elsif($args{undisclosed}) { $message->printUndisclosed($fh) }
    else                      { $message->Mail::Message::print($fh) }

    $self;
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

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.011.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
