
use strict;
package Mail::Box::POP3;
use base 'Mail::Box::Net';

our $VERSION = 2.017;

use Mail::Box::POP3::Message;

use IO::File;
use File::Spec;
use File::Basename;
use Carp;

=head1 NAME

Mail::Box::POP3 - handle POP3 folders as client

=head1 CLASS HIERARCHY

 Mail::Box::POP3
 is a Mail::Box::Net
 is a Mail::Box
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::POP3;
 my $folder = new Mail::Box::POP3 folder => $ENV{MAIL}, ...;

=head1 DESCRIPTION

WARNING: THE POP3 IMPLEMENTAION IS UNDER CONSTRUCTION: IT WILL *NOT*
WORK AT ALL!!!!

This documentation describes how POP3 mailboxes work, and what you
can do with the POP3 folder object C<Mail::Box::POP3>.
Please read C<Mail::Box-Overview> and C<Mail::Box> first.

L<The internal organization and details|/"IMPLEMENTATION"> are found
at the bottom of this manual-page.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Box> (MB), L<Mail::Reporter> (MR), L<Mail::Box::Net> (MBN).

The general methods for C<Mail::Box::POP3> objects:

   MB addMessage  MESSAGE               MB messageId MESSAGE-ID [,MESS...
   MB addMessages MESSAGE [, MESS...    MB messageIds
   MB close OPTIONS                     MB messages ['ALL',RANGE,'ACTI...
   MB copyTo FOLDER, OPTIONS            MB modified [BOOLEAN]
   MB create FOLDERNAME [, OPTIONS]     MB name
   MB current [NUMBER|MESSAGE|MES...       new OPTIONS
   MB delete                            MB openSubFolder NAME [,OPTIONS]
   MR errors                            MR report [LEVEL]
   MB find MESSAGE-ID                   MR reportAll [LEVEL]
   MB listSubFolders OPTIONS            MR trace [LEVEL]
   MB locker                            MR warnings
   MR log [LEVEL [,STRINGS]]            MB writable
   MB message INDEX [,MESSAGE]

The extra methods for extension writers:

   MR AUTOLOAD                          MB organization
   MB DESTROY                           MB read OPTIONS
   MB appendMessages OPTIONS           MBN readAllHeaders
   MB clone OPTIONS                     MB readMessages OPTIONS
   MB coerce MESSAGE                    MB scanForMessages MESSAGE, ME...
   MB determineBodyType MESSAGE, ...    MB sort PREPARE, COMPARE, LIST
   MB folderdir [DIR]                   MB storeMessage MESSAGE
   MB foundIn [FOLDERNAME], OPTIONS     MB timespan2seconds TIME
   MR inGlobalDestruction               MB toBeThreaded MESSAGES
   MB lineSeparator [STRING|'CR'|...    MB toBeUnthreaded MESSAGES
   MR logPriority LEVEL                 MB update OPTIONS
   MR logSettings                       MB updateMessages OPTIONS
   MR notImplemented                    MB write OPTIONS
   MB openRelatedFolder OPTIONS         MB writeMessages

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a new folder.  The are many options which are taken from other
objects.  For some, different options are set.  For POP3-specific options
see below, but first the full list.

 OPTION            DEFINED BY         DEFAULT
 access            Mail::Box          'r'
 authenicate       Mail::Box::POP3    'LOGIN'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          <not used>
 head_wrap         Mail::Box          72
 keep_dups         Mail::Box          0
 extract           Mail::Box          10kB
 lock_type         Mail::Box          <not used>
 lock_file         Mail::Box          <not used>
 lock_timeout      Mail::Box          <not used>
 lock_wait         Mail::Box          <not used>
 log               Mail::Reporter     'WARNINGS'
 password          Mail::Box::POP3    undef
 pop_client        Mail::Box::POP3    undef
 pop_server        Mail::Box::POP3    undef
 server_port       Mail::Box::POP3    110
 remove_when_empty Mail::Box          <never>
 save_on_exit      Mail::Box          1
 trace             Mail::Reporter     'WARNINGS'
 trusted           Mail::Box          0
 user              Mail::Box::POP3    undef

Only useful to write extension to C<Mail::Box::POP3>.  Common users of
folders you will not specify these:

 OPTION            DEFINED BY         DEFAULT
 body_type         Mail::Box::Net     <see Mail::Box::Net>
 body_delayed_type Mail::Box          'Mail::Message::Body::Delayed'
 coerce_options    Mail::Box          []
 field_type        Mail::Box          undef
 head_type         Mail::Box          'Mail::Message::Head::Complete'
 head_delayed_type Mail::Box          'Mail::Message::Head::Delayed'
 locker            Mail::Box          undef
 multipart_type    Mail::Box          'Mail::Message::Body::Multipart'
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::POP3::Message'
 realhead_type     Mail::Box          'Mail::Message::Head'

POP3 specific options are described below.  For authentications, you
have three choices: specify a foldername which resembles an URL, or
specify a pop-client object, or separate options for user, password,
pop-server and server-port.

=over 4

=item * authenticate =E<gt> 'LOGIN'|'APOP'

POP3 can use two methods of authentication: the old LOGIN protocol, which
transmits a username and password in plain text, and the newer APOP
protocol which uses MD5 encryption.  APOP is therefore much better, however
not always supported by the server.

=item * password =E<gt> STRING

The password string for authentication.

=item * pop_client =E<gt> OBJECT

You may want to specify your own pop-client object.  The object
which is passed must extend C<Mail::Transport::POP3>.

=item * pop_server =E<gt> HOSTNAME

The HOSTNAME of the POP3 server.

=item * server_port =E<gt> PORTNUMBER

The PORT behind which the POP3 daemon is running on the pop-server host.

=item * user =E<gt> STRING

The user's name to login on the POP3 server.

=back

Examples:

 my $pop = Mail::Box::POP3->new('pop3://pop.xs4all.nl;user@passwd');

 my $pop = $mgr->open(type => 'pop3', user => 'myname',
    password => 'mypassword', host => 'pop-host');

=cut

my $default_folder_dir = exists $ENV{HOME} ? "$ENV{HOME}/.POP3" : '.';

sub init($)
{   my ($self, $args) = @_;

    $args->{trusted} ||= 0;

    $self->SUPER::init($args);

    # About the authentication.

    my ($client, $foldername);
    if($client = $args->{pop_client}) { $foldername = $client->url }
    elsif($args->{folder})            { $foldername = $args->{folder} }
    else
    {   my $user = defined $args->{user} ? $args->{user}
            : croak "Username required for POP3 login.";

        my $password = defined $args->{password} ? $args->{password}
            : croak "Password required for POP3 login.";

        my $host = $args->{pop_server}
            or croak "The hostname of the POP3 server must be specified.";

        my $port = $args->{server_port}  || 110;
        $foldername = "pop3://$host:$port;$user@$password";
    }

    unless($client)
    {   my $auth = $args->{authenticate} || 'LOGIN';

        require Mail::Transport::POP3;
        $client  = Mail::Transport::POP3->new
          ( $foldername
          , authenticate => $auth
          );

        unless($client)
        {   $self->log(ERROR => "Unable to connect to $foldername.");
            return undef;
        }

        $self->log(PROGRESS =>"Connection to $foldername established.");
    }

    $self->{MBP_client} = $client;
    $self;
}

#-------------------------------------------

sub create($@) { undef }         # fails

#-------------------------------------------

sub listSubFolders(@) { () }     # no

#-------------------------------------------

sub openSubFolder($@) { undef }  # fails

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

sub foundIn($@)
{   my ($self, $foldername) = @_;
    $foldername =~ m/^\s*pop3?\:/i;
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

sub writeMessages($@)
{   my ($self, $args) = @_;

    if(my $modifications = grep {$_->modfied} @{$args->{messages}})
    {   $self->log(WARNING =>
           "Update of $modifications messages ignored for pop3 folder $self.");
    }

    $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head2 How POP3-folders work

=head2 This implementation

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.017.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
