
use strict;
use warnings;

package Mail::Box::IMAP4;
use base 'Mail::Box::Net';

use Mail::Box::IMAP4::Message;
use Mail::Box::IMAP4::Head;
use Mail::Transport::IMAP4;

use Mail::Box::Parser::Perl;
use Mail::Message::Head::Complete;
use Mail::Message::Head::Delayed;

use Scalar::Util 'weaken';

=chapter NAME

Mail::Box::IMAP4 - handle IMAP4 folders as client

=chapter SYNOPSIS

 use Mail::Box::IMAP4;
 my $folder = new Mail::Box::IMAP4 folder => $ENV{MAIL}, ...;

=chapter DESCRIPTION

UNDER DEVELOPMENT!!!! LIMITATIONS:
=over 4
=item * this implementation is close to NOT TESTED!
Of course, some testing has been done, but this is far from complete. Please
contribute with ideas are problem reports.

=item * messages are all treated as separte items
Performance can be improved combining request for multiple subjects. For
instance, a preloadFields() or a preloadEnvelope() would speed-up most
applications
=back

Maintain a folder which has its messages stored on a remote server.  The
communication between the client application and the server is implemented
using the IMAP4 protocol.

This class uses M<Mail::Transport::IMAP4> to hide the transport of
information, and focusses solely on the correct handling of messages
within a IMAP4 folder.  More than one IMAP4 folder can be handled by
one single IMAP4 connection.

=chapter METHODS

=c_method new OPTIONS

The C<new> can have many OPTIONS.  Not only the ones listed here below,
but also all the OPTIONS for M<Mail::Transport::IMAP4::new()> can be
passed.

=default access 'r'

=default head_type M<Mail::Box::IMAP4::Head> or M<Mail::Message::Head::Complete>
The default depends on the value of M<new(cache_head)>.

=default folder C</>
Without folder name, no folder is selected.  Only few methods are
available now, for instance M<listSubFolders()> to get the top-level
folder names.  Usually, the folder named C<INBOX> will be present.

=default server_port  143
=default message_type M<Mail::Box::IMAP4::Message>

=option  transporter  OBJECT|CLASS
=default transporter  M<Mail::Transport::IMAP4>
The name of the CLASS which will interface with the connection.  When you
implement your own extension to M<Mail::Transport::IMAP4>, you can either
specify a fully instantiated transporter OBJECT, or the name of your own
CLASS.  When an OBJECT is given, most other options will be ignored.

=option  join_connection BOOLEAN
=default join_connection C<true>
Within this Mail::Box::IMAP4 class is registered which transporters are
already in use, i.e. which connections to the IMAP server are already
in established.  When this option is set, multiple folder openings on the
same server will try to reuse one connection.

=option  cache_labels 'NO'|'WRITE'|'DELAY'
=default cache_labels C<NO> or C<DELAY>
When labels from a message are received, these values can be kept. However,
this imposes dangers where the server's internal label storage may get out
of sync with your data.

With C<NO>, no caching will take place (but the performance will be
worse). With C<WRITE>, all label access will be cached, but written to
the server as well.  Both C<NO> and C<WRITE> will update the labels on
the served, even when the folder was opened read-only.  C<DELAY> will
not write the changed information to the server, but delay that till
the moment that the folder is closed.  It only works when the folder is
opened read/write or write is enforced.

The default is C<DELAY> for folders which where opened read-only.  This
means that you still can force an update with M<close(write)>.  For folders
which are opened read-write, the default is the safeset setting, which is
C<NO>.

=option  cache_head 'NO'|'PARTIAL'|'DELAY'
=default cache_head C<NO> or C<DELAY>
For a read-only folder, C<DELAY> is the default, otherwise C<NO> is
choosen.  The four configuration parameter have subtile consequences.
To start with a table:

        [local cache]  [write]  [default head_type]
 NO         no           no     M<Mail::Box::IMAP4::Head>
 PARTIAL    yes          no     M<Mail::Box::IMAP4::Head>
 DELAY      yes          yes    M<Mail::Message::Head::Complete>

The default C<head_type> is M<Mail::Box::IMAP4::Head>, the
default C<cached_head_type> is M<Mail::Message::Head::Complete>.

Having a local cache means that a lookup for a field is first done
in a local data-structure (which extends M<Mail::Message::Head::Partial>),
and only on the remote server if it was not found.  This is dangerous,
because your locally cached data can be out-of-sync with the server.
However, it may give you a nice performance benefit.

C<DELAY> will always collect the whole
header for you.  This is required when you want to look for Resent Groups
(See M<Mail::Message::Head::ResentGroup>) or other field order dependent
header access.  A M<Mail::Message::Head::Delayed> will be created first.

=option  cache_body 'NO'|'YES'|'DELAY'
=default cache_body C<NO>
Body objects are immutable, but may still cached or not.  In common
case, the body of a message is requested via M<Mail::Message::body()>
or M<Mail::Message::decoded()>.  This returns a handle to a body object.
You may decide wether that body object can be reused or not.  C<NO>
means: retreive the data each time again, C<YES> will cache the body data,
C<DELAY> will send the whole message when the folder is closed.

        [local cache]  [write]
 NO         no           no
 YES        yes          no
 DELAY      yes          yes

=examples
 my $imap   = Mail::Box::IMAP4->new(username => 'myname',
    password => 'mypassword', server_name => 'imap.xs4all.nl');

 my $url    = 'imap4://user:password@imap.xs4all.nl');
 my $imap   = $mgr->open($url);

 my $client = Mail::IMAPClient->new(...);
 my $imap   = Mail::Box::IMAP4->new(imap_client => $client);

=cut

sub init($)
{   my ($self, $args) = @_;

    # Need some prediction for correct defaults
    my $access    = $args->{access} ||= 'r';
    my $writeable = $access =~ m/w|a/;
    my $ch        = $self->{MBI_c_head}
      = $args->{cache_head} || ($writeable ? 'NO' : 'DELAY');

    $args->{head_type} ||= 'Mail::Box::IMAP4::Head'
       if $ch eq 'NO' || $ch eq 'PARTIAL';

    $args->{body_type}  ||= 'Mail::Message::Body::Lines';

    $self->SUPER::init($args);

    $self->{MBI_domain}   = $args->{domain};
    $self->{MBI_c_labels} = $args->{cache_labels}
                         || ($writeable  ? 'NO' : 'DELAY');
    $self->{MBI_c_body}   = $args->{cache_body}
                         || ($writeable ? 'NO' : 'DELAY');


    my $transport = $args->{transporter} || 'Mail::Transport::IMAP4';
    unless(ref $transport)
    {   eval "require $transport";
        $self->log(ERROR => "Cannot install transporter $transport:\n$@\n"),
           return () if $@;

        $transport = $self->createTransporter($transport, %$args)
	    or return undef;
    }

    $self->transporter($transport);
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

=method close OPTIONS
Close the folder.  In the case of IMAP, more than one folder can use
the same connection, therefore, closing a folder does not always close
the connection to the server.  Only when no folder is using the
connection anymore, a logout will be invoked by
M<Mail::Transport::IMAP4::DESTROY()>
=cut

sub close(@)
{   my $self = shift;
    $self->SUPER::close(@_) or return ();
    $self->transporter(undef);
    $self;
}

#-------------------------------------------

sub listSubFolders(@)
{   my ($thing, %args) = @_;
    my $self = $thing;

    $self = $thing->new(%args) or return ()  # list toplevel
        unless ref $thing;

    my $imap = $self->transporter;
    defined $imap ? $imap->folders($self) : ();
}

#-------------------------------------------

sub nameOfSubfolder($)
{   my ($self, $name) = @_;
    $name;
}

#-------------------------------------------

=section Internals

=cut

sub readMessages(@)
{   my ($self, %args) = @_;

    my $name  = $self->name;
    return $self if $name eq '/';

    my $imap  = $self->transporter;
    my @log   = $self->logSettings;
    my $seqnr = 0;

    my $cl    = $self->{MBI_c_labels} ne 'NO';
    my $wl    = $self->{MBI_c_labels} ne 'DELAY';

    my $ch    = $self->{MBI_c_head};
    my $ht    = $ch eq 'DELAY' ? $args{head_delayed_type} : $args{head_type};
    my @ho    = $ch eq 'PARTIAL' ? (cache_fields => 1) : ();

    foreach my $id ($imap->ids)
    {   my $head    = $ht->new(@log, @ho);
        my $message = $args{message_type}->new
         ( head      => $head
         , unique    => $id
         , folder    => $self
         , seqnr     => $seqnr++

	 , cache_labels => $cl
	 , write_labels => $wl
         , cache_head   => ($ch eq 'DELAY')
         , cache_body   => ($ch ne 'NO')
         );

        my $body    = $args{body_delayed_type}
           ->new(@log, message => $message);

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
    my $imap   = $self->transporter or return;

    my $uidl   = $message->unique;
    my @fields = $imap->getFields($uidl, 'ALL');

    unless(@fields)
    {   $self->log(WARNING => "Message $uidl disappeared from $self.");
        return;
    }

    my $head = $self->{MB_head_type}->new;
    $head->addNoRealize($_) for @fields;

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
    my $imap  = $self->transporter or return;
    my $uid   = $message->unique;
    my $lines = $imap->getMessageAsString($uid);

    unless(defined $lines)
    {   $self->log(WARNING => "Message $uid disappeared from $self.");
        return ();
     }

    my $parser = Mail::Box::Parser::Perl->new   # not parseable by C parser
     ( filename  => "$imap"
     , file      => Mail::Box::FastScalar->new(\$lines)
     );

    my $head = $message->readHead($parser);
    unless(defined $head)
    {   $self->log(WARNING => "Cannot find head back for $uid in $self.");
        $parser->stop;
        return ();
    }

    my $body = $message->readBody($parser, $head);
    unless(defined $body)
    {   $self->log(WARNING => "Cannot read body for $uid in $self.");
        $parser->stop;
        return ();
    }

    $parser->stop;

    $self->log(PROGRESS => "Loaded message $uid.");
    ($head, $body->contentInfoFrom($head));
}

#-------------------------------------------

=method body [BODY]

=cut

sub body(;$)
{   my $self = shift;
    unless(@_)
    {   my $body = $self->{MBI_cache_body} ? $self->SUPER::body : undef;
    }

    $self->unique();
    $self->SUPER::body(@_);
}

#-------------------------------------------


=method write OPTIONS
The IMAP protocol usually writes the data immediately to the remote server,
because that's what the protocol wants.  However, some options to M<new()>
may delay that to boost performance.  This method will, when the folder is
being closed, write that info after all.

=option save_deleted BOOLEAN
You may be able to save the messages which are flagged for deletion now,
but they will be removed anyway when the folder is closed.

=notice Impossible to keep deleted messages in IMAP
Some folder type have a 'deleted' flag which can be stored in the folder to
be performed later.  The folder keeps that knowledge even when the folder
is rewritten.  Well, IMAP4 cannot play that trick.

=cut

sub write(@)
{   my ($self, %args) = @_;
    my $imap  = $self->transporter or return;

    $self->SUPER::write(%args, transporter => $imap) or return;

    if($args{save_deleted})
    {   $self->log(NOTICE => "Impossible to keep deleted messages in IMAP")
    }
    else { $imap->destroyDeleted }

    $self;
}

#-------------------------------------------

=method writeMessages OPTIONS
=requires transporter OBJECT
=cut

sub writeMessages($@)
{   my ($self, $args) = @_;

    my $imap = $args->{transporter};
    my $fn   = $self->name;

    $_->writeDelayed($fn, $imap) for @{$args->{messages}};

    $self;
}

#-------------------------------------------

=method createTransporter CLASS, OPTIONS
Create a transporter object (an instance of M<Mail::Transport::IMAP4>), where
CLASS defines the exact object type.  As OPTIONS, everything which is
acceptable to a transporter initiation can be used (see
M<Mail::Transport::IMAP4::new()>.

=option  join_connection BOOLEAN
=default join_connection C<true>
See M<new(join_connection)>.  When false, the connection will never be shared
with other IMAP mail boxes.

=cut

my %transporters;
sub createTransporter($@)
{   my ($self, $class, %args) = @_;

    my $hostname = $self->{MBN_hostname} || 'localhost';
    my $port     = $self->{MBN_port}     || '143';
    my $username = $self->{MBN_username} || $ENV{USER};

    my $join     = exists $args{join_connection} ? $args{join_connection} : 1;

    my $linkid;
    if($join)
    {   $linkid  = "$hostname:$port:$username";
        return $transporters{$linkid} if defined $transporters{$linkid};
    }

    my $transporter = $class->new
     ( %args,
     , hostname => $hostname, port     => $port
     , username => $username, password => $self->{MBN_password}
     , domain   => $self->{MBI_domain}
     ) or return undef;

    if(defined $linkid)
    {   $transporters{$linkid} = $transporter;
        weaken($transporters{$linkid});
    }

    $transporter;
}

#-------------------------------------------

=method transporter [OBJECT]
Returns the object which is the interface to the IMAP4 protocol handler.
The IMAP4 handler has the current folder selected.
When an OBJECT is specified, it is set to be the transporter from
that moment on.  The OBJECT must extend M<Mail::Transport::IMAP4>.

=cut

sub transporter(;$)
{   my $self = shift;
    my $imap = @_ ? ($self->{MBI_transport} = shift) : $self->{MBI_transport};
    return unless defined $imap;

    my $name = $self->name;
    $imap->folder($name) unless $name eq '/';

    $imap;
}

#-------------------------------------------

=method fetch ARRAY-OF-MESSAGES|MESSAGE-SELECTION, INFO
Low-level data retreival about one or more messages via IMAP4 from
the remote server. Some of this data may differ from the information
which is stored in the message objects which are created by MailBox,
so you should avoid the use of this method for your own purposes.
The IMAP implementation provides some wrappers around this, providing
the correct behavior.

An array of MESSAGES may be specified or some MESSAGE SELECTION,
acceptable to M<Mail::Box::messages()>.  Examples of the latter are
C<'ALL'>, C<'DELETED'>, or C<spam> (messages labelled to contain spam).

The INFO contains one or more attributes as defined by the IMAP protocol.
You have to read the full specs of the related RFCs to see these.

=cut

sub fetch($@)
{   my ($self, $what, @info) = @_;
    my $imap = $self->transporter or return [];
    $what = $self->messages($what) unless ref $what eq 'ARRAY';
    $imap->fetch($what, @info);
}

#-------------------------------------------

=section Error handling

=chapter DETAILS

=section How IMAP4 folders work

=cut

1;
