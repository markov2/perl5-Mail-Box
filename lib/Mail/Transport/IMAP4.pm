
use strict;
use warnings;

package Mail::Transport::IMAP4;
use base 'Mail::Transport::Receive';

use Digest::HMAC_MD5;   # only availability check for CRAM_MD5
use Mail::IMAPClient;
use List::Util        qw/first/;

=chapter NAME

Mail::Transport::IMAP4 - proxy to Mail::IMAPClient

=chapter SYNOPSIS

 my $imap = Mail::Transport::IMAP4->new(...);
 my $message = $imap->receive($id);
 $imap->send($message);

=chapter DESCRIPTION

The IMAP4 protocol is quite complicated: it is feature rich and allows
verious asynchronous actions.  The main document describing IMAP is
rfc3501 (which obsoleted the original specification of protocol 4r1
in rfc2060 in March 2003).

This package, as part of MailBox, does not implement the actual
protocol itself but uses M<Mail::IMAPClient> to do the work. The task
for this package is to hide as many differences between that module's
interface and the common MailBox folder types.  Multiple
M<Mail::Box::IMAP4> folders can share one M<Mail::Transport::IMAP4>
connection.

The M<Mail::IMAPClient> module is the best IMAP4 implementation for
Perl5, but is not maintained.  There are many known problems with the
module, and solving those is outside the scope of MailBox.  See
F<http://rt.cpan.org/Public/Dist/Display.html?Name=Mail-IMAPClient>
for all the reported bugs.

=chapter METHODS

=c_method new %options

Create the IMAP connection to the server.  IMAP servers can handle
multiple folders for a single user, which means that connections
may get shared.  This is sharing is hidden for the user.

When an C<imap_client> is specified, then the options C<hostname>,
C<port>, C<username>, and C<password> are extracted from it.

=default port 143
=default via  C<'imap'>

=option  authenticate TYPE|ARRAY
=default authenticate C<'AUTO'>
Authenthication method to M<login()>, which will be passed to
M<Mail::IMAPClient::authenticate()>.  See the latter method for
the available types.  You may provide an ARRAY of types.

=option  domain WINDOWS_DOMAIN
=default domain <server_name>
Used for NTLM authentication.

=option  imap_client OBJECT|CLASS
=default imap_client L<Mail::IMAPClient|Mail::IMAPClient>
When an OBJECT is supplied, that client will be used for the implementation
of the IMAP4 protocol. Information about server and such are extracted from
the OBJECT to have the accessors to produce correct results. The OBJECT
shall be a L<Mail::IMAPClient|Mail::IMAPClient>.

When a CLASS is given, an object of that type is created for you.  The created
object can be retrieved via M<imapClient()>, and than configured as
defined by L<Mail::IMAPClient|Mail::IMAPClient>.

=option  starttls BOOLEAN
=default starttls C<false>
tart Transport Security Layer (TLS).
=cut

sub init($)
{   my ($self, $args) = @_;

    my $imap = $args->{imap_client} || 'Mail::IMAPClient';
    if(ref $imap)
    {   $args->{port}     = $imap->Port;
        $args->{hostname} = $imap->Server;
	$args->{username} = $imap->User;
	$args->{password} = $imap->Password;
    }
    else
    {   $args->{port}   ||= 143;
    }

    $args->{via}          = 'imap4';

    $self->SUPER::init($args) or return;

    $self->authentication($args->{authenticate} || 'AUTO');
    $self->{MTI_domain} = $args->{domain};

    unless(ref $imap)
    {   $imap = $self->createImapClient($imap, Starttls => $args->{starttls})
             or return undef;
    }
 
    $self->imapClient($imap) or return undef;
    $self->login             or return undef;
}

=method url
Represent this imap4 connection as URL.
=cut

sub url()
{   my $self = shift;
    my ($host, $port, $user, $pwd) = $self->remoteHost;
    my $name = $self->folderName;
    "imap4://$user:$pwd\@$host:$port$name";
}

#------------------------------------------

=section Attributes

=method authentication ['AUTO'|$type|$types]
Returns a LIST of ARRAYS, each describing one possible way to contact
the server. Each pair contains a mechanism name and a challenge callback
(which may be C<undef>).

The settings are used by M<login()> to get server access.  The initial
value origins from M<new(authenticate)>, but may be changed later.

Available basic $types are C<CRAM-MD5>, C<NTLM>, and C<PLAIN>.  With
C<AUTO>, all available types will be tried.  When the M<Authen::NTLM>
is not installed, the C<NTLM> option will silently be skipped.  Be warned
that, because of C<PLAIN>, erroneous username/password combinations will
be passed readible as last attempt!

The C<NTLM> authentication requires M<Authen::NTLM> to be installed.  Other
methods may be added later.  Besides, you may also specify a CODE
reference which implements some authentication.

An ARRAY as $type can be used to specify both mechanism as callback.  When
no array is used, callback of the pair is set to C<undef>.  See
L<Mail::IMAPClient/authenticate> for the gory details.

=examples
 $transporter->authentication('CRAM-MD5', [MY_AUTH => \&c], 'PLAIN');

 foreach my $pair ($transporter->authentication)
 {   my ($mechanism, $challange) = @$pair;
     ...
 }

=cut

sub authentication(@)
{   my ($self, @types) = @_;

    # What the client wants to use to login

    unless(@types)
    {   @types = exists $self->{MTI_auth} ? @{$self->{MTI_auth}} : 'AUTO';
    }

    if(@types == 1 && $types[0] eq 'AUTO')
    {   @types = qw/CRAM-MD5 DIGEST-MD5 PLAIN NTLM LOGIN/;
    }

    $self->{MTI_auth} = \@types;

    my @clientside;
    foreach my $auth (@types)
    {   push @clientside
         , ref $auth eq 'ARRAY' ? $auth
         : $auth eq 'NTLM'      ? [NTLM  => \&Authen::NTLM::ntlm ]
         :                        [$auth => undef];
    }

    my %clientside = map { ($_->[0] => $_) } @clientside;

    # What does the server support? in its order of preference.

    my $imap = $self->imapClient or return ();
    my @serverside = map { m/^AUTH=(\S+)/ ? uc($1) : () }
                        $imap->capability;

    my @auth;
    if(@serverside)  # server list auth capabilities
    {   @auth = map { $clientside{$_} ? delete $clientside{$_} : () }
             @serverside;
    }
    @auth = @clientside unless @auth;  # fallback to client's preference

    @auth;
}

=method domain [$domain]
Used in NTLM authentication to define the Windows domain which is
accessed.  Initially set by M<new(domain)> and defaults to the
server's name.
=cut

sub domain(;$)
{   my $self = shift;
    return $self->{MTI_domain} = shift if @_;
    $self->{MTI_domain} || ($self->remoteHost)[0];
}

#------------------------------------------

=section Exchanging Information

=section Protocol [internals]

The follow methods handle protocol internals, and should not be used
by a normal user of this class.

=method imapClient
Returns the object which implements the IMAP4 protocol, an instance
of a M<Mail::IMAPClient>, which is logged-in and ready to use.

If the contact to the server was still present or could be established,
an M<Mail::IMAPClient> object is returned.  Else, C<undef> is returned and
no further actions should be tried on the object.
=cut

sub imapClient(;$)
{   my $self = shift;
    @_ ? ($self->{MTI_client} = shift) : $self->{MTI_client};
}

=method createImapClient $class, %options
Create an object of $class, which extends L<Mail::IMAPClient>.

All %options will be passed to the constructor (new) of $class.

=cut

sub createImapClient($@)
{   my ($self, $class, @args) = @_;

    my ($host, $port) = $self->remoteHost;

    my $debug_level = $self->logPriority('DEBUG')+0;
    if($self->log <= $debug_level || $self->trace <= $debug_level)
    {   tie *dh, 'Mail::IMAPClient::Debug', $self;
        push @args, Debug => 1, Debug_fh => \*dh;
    }

    my $client = $class->new
      ( Server => $host, Port => $port
      , User   => undef, Password => undef   # disable auto-login
      , Uid    => 1                          # Safer
      , Peek   => 1                          # Don't set \Seen automaticly
      , @args
      );

    $self->log(ERROR => $@), return undef if $@;
    $client;
}

=method login
Establish a new connection to the IMAP4 server, using username and password.

=error  IMAP4 requires a username and password
=error  IMAP4 username $username requires a password
=error  Cannot connect to $host:$port for IMAP4: $!
=notice IMAP4 authenication $mechanism to $host:$port successful
=error  IMAP cannot connect to $host: $@

=cut

sub login(;$)
{   my $self = shift;
    my $imap = $self->imapClient;

    return $self if $imap->IsAuthenticated;

    my ($interval, $retries, $timeout) = $self->retry;

    my ($host, $port, $username, $password) = $self->remoteHost;
    unless(defined $username)
    {   $self->log(ERROR => "IMAP4 requires a username and password");
        return;
    }
    unless(defined $password)
    {   $self->log(ERROR => "IMAP4 username $username requires a password");
        return;
    }

    while(1)
    {
        foreach my $auth ($self->authentication)
        {   my ($mechanism, $challange) = @$auth;

            $imap->User(undef);
            $imap->Password(undef);
            $imap->Authmechanism(undef);   # disable auto-login
            $imap->Authcallback(undef);

            unless($imap->connect)
	    {   $self->log(ERROR => "IMAP cannot connect to $host: "
	                          , $imap->LastError);
		return undef;
	    }

            $imap->User($username);
            $imap->Password($password);
            $imap->Authmechanism($mechanism);
            $imap->Authcallback($challange) if defined $challange;

            if($imap->login)
            {
	       $self->log(NOTICE =>
        "IMAP4 authenication $mechanism to $username\@$host:$port successful");
                return $self;
            }
        }

        $self->log(ERROR => "Couldn't contact to $username\@$host:$port")
            , return undef if $retries > 0 && --$retries == 0;

        sleep $interval if $interval;
    }

    undef;
}

=method currentFolder [$foldername]
Be sure that the specific FOLDER is the current one selected.  If the
folder is already selected, no IMAP traffic will be produced.

The boolean return value indicates whether the folder is selectable. It
will return undef if it does not exist.
=cut

sub currentFolder(;$)
{   my $self = shift;
    return $self->{MTI_folder} unless @_;

    my $name = shift;

    if(defined $self->{MTI_folder} && $name eq $self->{MTI_folder})
    {   $self->log(DEBUG => "Folder $name already selected.");
        return $name;
    }

    # imap first deselects the old folder so if the next call
    # fails the server will not have anything selected.
    $self->{MTI_folder} = undef;

    my $imap = $self->imapClient or return;

    if($name eq '/' || $imap->select($name))
    {   $self->{MTI_folder} = $name;
        $self->log(NOTICE => "Selected folder $name");
        return 1;
    }

    # Just because we couldn't select the folder that doesn't mean it doesn't
    # exist.  It just means that this particular imap client is warning us
    # that it can't contain messages.  So we'll verify that it does exist
    # and, if so, we'll pretend like we could have selected it as if it were
    # a regular folder.
    # IMAPClient::exists() only works reliably for leaf folders so we need
    # to grep for it ourselves.

    if(first { $_ eq $name } $self->folders)
    {   $self->{MTI_folder} = $name;
        $self->log(NOTICE => "Couldn't select $name but it does exist.");
        return 0;
    }

    $self->log(NOTICE => "Folder $name does not exist!");
    undef;
}

=method folders [$foldername]
Returns a list of folder names which are sub-folders of the specified
$foldername.  Without $foldername, the top-level foldernames are returned.
=cut

sub folders(;$)
{   my $self = shift;
    my $top  = shift;

    my $imap = $self->imapClient or return ();
    $top = undef if defined $top && $top eq '/';

    # We need to force the remote IMAP client to only return folders
    # *underneath* the folder we specify.  By default they want to return
    # all folders.
    # Alas IMAPClient always appends the separator so, despite what it says
    # in its own docs, there's purpose to doing this.  We just need
    # to get whatever we get and postprocess it.  ???Still true???
    my @folders = $imap->folders($top);

    # We need to post-process the list returned by IMAPClient.
    # This selects out the level of directories we're interested in.
    my $sep   = $imap->separator;
    my $level = 1 + (defined $top ? () = $top =~ m/\Q$sep\E/g : -1);

    # There may be duplications, thanks to subdirs so we uniq it
    my %uniq;
    $uniq{(split /\Q$sep\E/, $_)[$level] || ''}++ for @folders;
    delete $uniq{''};

    keys %uniq;
}

=method ids
Returns a list of UIDs which are defined by the IMAP server.
=cut

sub ids($)
{   my $self = shift;
    my $imap = $self->imapClient or return ();
    $imap->messages;
}

=method getFlags $folder, $id
Returns the values of all flags which are related to the message with the
specified $id.  These flags are translated into the names which are
standard for the MailBox suite.

A HASH is returned.  Names which do not appear will also provide
a value in the returned: the negative for the value is it was present.
=cut

# Explanation in Mail::Box::IMAP4::Message chapter DETAILS

my %flags2labels =
 ( # Standard IMAP4 labels
   '\Seen'     => [seen     => 1]
 , '\Answered' => [replied  => 1]
 , '\Flagged'  => [flagged  => 1]
 , '\Deleted'  => [deleted  => 1]
 , '\Draft'    => [draft    => 1]
 , '\Recent'   => [old      => 0]

   # For the Netzwert extension (Mail::Box::Netzwert), some labels were
   # added.  You'r free to support them as well.
 , '\Spam'     => [spam     => 1]
 );

my %labels2flags;
while(my ($k, $v) = each %flags2labels)
{  $labels2flags{$v->[0]} = [ $k => $v->[1] ];
}

# where IMAP4 supports requests for multiple flags at once, we here only
# request one set of flags a time (which will be slower)

sub getFlags($$)
{   my ($self, $id) = @_;
    my $imap   = $self->imapClient or return ();
    my $labels = $self->flagsToLabels(SET => $imap->flags($id));

    # Add default values for missing flags
    foreach my $s (values %flags2labels)
    {   $labels->{$s->[0]} = not $s->[1]
             unless exists $labels->{$s->[0]};
    }

    $labels;
}

=method listFlags
Returns all predefined flags as list.
=cut

sub listFlags() { keys %flags2labels }

=method setFlags $id, $label, $value, [$label, $value], ...
Change the flags on the message which are represented by the label.  The
value which can be related to the label will be lost, because IMAP only
defines a boolean value, where MailBox labels can contain strings.

Returned is a list of $label=>$value pairs which could not be send to
the IMAP server.  These values may be cached in a different way.
=cut

# Mail::IMAPClient can only set one value a time, however we do more...
sub setFlags($@)
{   my ($self, $id) = (shift, shift);

    my $imap = $self->imapClient or return ();
    my (@set, @unset, @nonstandard);

    while(@_)
    {   my ($label, $value) = (shift, shift);
        if(my $r = $labels2flags{$label})
        {   my $flag = $r->[0];
            $value = $value ? $r->[1] : !$r->[1];
	        # exor can not be used, because value may be string
            $value ? (push @set, $flag) : (push @unset, $flag);
        }
	else
	{   push @nonstandard, ($label => $value);
        }
    }

    $imap->set_flag($_, $id)   foreach @set;
    $imap->unset_flag($_, $id) foreach @unset;

    @nonstandard;
}

=ci_method labelsToFlags HASH|PAIRS
Convert MailBox labels into IMAP flags.  Returned is a string.  Unsupported
labels are ignored.
=cut

sub labelsToFlags(@)
{   my $thing = shift;
    my @set;
    if(@_==1)
    {   my $labels = shift;
        while(my ($label, $value) = each %$labels)
        {   if(my $r = $labels2flags{$label})
            {   push @set, $r->[0] if ($value ? $r->[1] : !$r->[1]);
            }
        }
    }
    else
    {   while(@_)
        {   my ($label, $value) = (shift, shift);
            if(my $r = $labels2flags{$label})
            {   push @set, $r->[0] if ($value ? $r->[1] : !$r->[1]);
            }
        }
    }

    join " ", sort @set;
}

=ci_method flagsToLabels $what|$flags
In SCALAR context, a hash with labels is returned.  In LIST context, pairs
are returned.

The $what parameter can be C<'SET'>, C<'CLEAR'>, or C<'REPLACE'>.  With the
latter, all standard imap flags do not appear in the list will be ignored:
their value may either by set or cleared.  See M<getFlags()>

Unknown flags in LIST are stripped from their backslash and lower-cased.
For instance, '\SomeWeirdFlag' will become `someweirdflag => 1'.

=examples translating IMAP4 flags into MailBox flags
 my @flags  = ('\Seen', '\Flagged');
 my $labels = Mail::Transport::IMAP4->flags2labels(SET => @flags);

=cut

sub flagsToLabels($@)
{   my ($thing, $what) = (shift, shift);
    my %labels;

    my $clear = $what eq 'CLEAR';

    foreach my $f (@_)
    {   if(my $lab = $flags2labels{$f})
        {   $labels{$lab->[0]} = $clear ? not($lab->[1]) : $lab->[1];
        }
        else
        {   (my $lab = $f) =~ s,^\\,,;
            $labels{$lab}++;
        }
    }

    if($what eq 'REPLACE')
    {   my %found = map { ($_ => 1) } @_;
        foreach my $f (keys %flags2labels)
        {   next if $found{$f};
            my $lab = $flags2labels{$f};
            $labels{$lab->[0]} = not $lab->[1];
        }
    }

    wantarray ? %labels : \%labels;
}

=method getFields $uid, $name, [$name, ...]
Get the records with the specified NAMES from the header.  The header
fields are returned as list of M<Mail::Message::Field::Fast> objects.
When the name is C<ALL>, the whole header is returned.
=cut

sub getFields($@)
{   my ($self, $id) = (shift, shift);
    my $imap   = $self->imapClient or return ();
    my $parsed = $imap->parse_headers($id, @_) or return ();

    my @fields;
    while(my($n,$c) = each %$parsed)
    {   push @fields, map { Mail::Message::Field::Fast->new($n, $_) } @$c;
    }

    @fields;
}

=method getMessageAsString $message|$uid
Returns the whole text of the specified message: the head and the body.
=cut

sub getMessageAsString($)
{   my $imap = shift->imapClient or return;
    my $uid = ref $_[0] ? shift->unique : shift;
    $imap->message_string($uid);
}

=method fetch ARRAY-$of-$messages, $info
Get some $info about the $messages from the server.  The specified messages
shall extend M<Mail::Box::Net::Message>, Returned is a list
of hashes, each info about one result.  The contents of the hash
differs per $info, but at least a C<message> field will be present, to
relate to the message in question.

The right folder should be selected before this method is called. When
the connection was lost, C<undef> is returned.  Without any
messages, and empty array is returned.  The retrieval is done by
L<Mail::IMAPClient|Mail::IMAPClient> method C<fetch()>, which is then
parsed.

=cut

sub fetch($@)
{   my ($self, $msgs, @info) = @_;
    return () unless @$msgs;
    my $imap   = $self->imapClient or return ();

    my %msgs   = map { ($_->unique => {message => $_} ) } @$msgs;
    my $lines  = $imap->fetch( [keys %msgs], @info );

    # It's a pity that Mail::IMAPClient::fetch_hash cannot be used for
    # single messages... now I had to reimplement the decoding...
    while(@$lines)
    {   my $line = shift @$lines;
        next unless $line =~ /\(.*?UID\s+(\d+)/i;
	my $id   = $+;
	my $info = $msgs{$id} or next;  # wrong uid

        if($line =~ s/^[^(]* \( \s* //x )
        {   while($line =~ s/(\S+)   # field
	                     \s+
                             (?:     # value
                                 \" ( (?:\\.|[^"])+ ) \"
                               | \( ( (?:\\.|[^)])+ ) \)
                               |  (\w+)
                             )//xi)
            {   $info->{uc $1} = $+;
            }

	    if( $line =~ m/^\s* (\S+) [ ]*$/x )
	    {   # Text block expected
	        my ($key, $value) = (uc $1, '');
	        while(@$lines)
		{   my $extra = shift @$lines;
		    $extra =~ s/\r\n$/\n/;
		    last if $extra eq ")\n";
		    $value .= $extra;
		}
		$info->{$key} = $value;
            }
        }

    }

    values %msgs;
}

=method appendMessage $message, $foldername, [$date]
Write the message to the server.
The optional DATA can be a RFC-822 date or a timestamp.
=cut

sub appendMessage($$)
{   my ($self, $message, $foldername, $date) = @_;
    my $imap = $self->imapClient or return ();

    $date    = $imap->Rfc_822($date)
        if $date && $date !~ m/\D/;

    $imap->append_string
     ( $foldername, $message->string
     , $self->labelsToFlags($message->labels)
     , $date
     );
}

=method destroyDeleted $folder
Command the server to delete for real all messages which are flagged to
be deleted.
=cut

sub destroyDeleted($)
{   my ($self, $folder) = @_;
    defined $folder or return;

    my $imap = shift->imapClient or return;
    $imap->expunge($folder);
}

=method createFolder $name
Add a folder.
=cut

sub createFolder($)
{   my $imap = shift->imapClient or return ();
    $imap->create(shift);
}

=method deleteFolder $name
Remove one folder.
=cut

sub deleteFolder($)
{   my $imap = shift->imapClient or return ();
    $imap->delete(shift);
}

=section Error handling

=section Cleanup

=method DESTROY

The connection is cleanly terminated when the program is
terminated.

=cut

sub DESTROY()
{   my $self = shift;
    my $imap = $self->imapClient;

    $self->SUPER::DESTROY;
    $imap->logout if defined $imap;
}

#------------------------------------------

# Tied filehandle translates IMAP's debug system into Mail::Reporter
# calls.
sub  Mail::IMAPClient::Debug::TIEHANDLE($)
{   my ($class, $logger) = @_;
    bless \$logger, $class;
}

sub  Mail::IMAPClient::Debug::PRINT(@)
{   my $logger = ${ (shift) };
    $logger->log(DEBUG => @_);
}

1;
