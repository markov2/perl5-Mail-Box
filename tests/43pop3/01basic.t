use Test::More tests => 18;
use File::Copy;

BEGIN { use_ok('Mail::Transport::POP3') }

# Check if all methods are there OK

can_ok('Mail::Transport::POP3', qw(
 deleted
 deleteFetched
 DESTROY
 disconnect
 fetched
 folderSize
 header
 ids
 id2n
 init
 message
 messages
 messageSize
 send
 sendList
 socket
 url
));

# Setup a mailbox

my $serverscript = '43pop3/server';
my $original = '43pop3/original';
my $popbox = '43pop3/popbox';

mkdir $popbox; # be lenient in case previous test bombed
ok(-d $popbox, "Directory $popbox does not exist") ;

my $error = '';
foreach my $from (<$original/????>)
{   (my $to = $from) =~ s#^$original#$popbox#o;
    $error = $! unless copy( $from,$to );
}
ok(!$error,
 "Could not copy one or more files from $original to $popbox: $error");

# Setup the POP server

ok(open(my $server, "$^X $serverscript $popbox|"),
 "Could not start POP3 server");
my $port = <$server>; $port =~ s#\r?\n$##;
ok( $port =~ m#^\d+$#, 'Did not get port specification');

my $receiver = Mail::Transport::POP3->new(
 hostname => '127.0.0.1',
 port     => $port,
 username => 'user',
 password => 'password',
);
isa_ok($receiver, 'Mail::Transport::POP3');

my $socket = $receiver->socket;
ok($socket, "Could not get socket of POP3 server");
print $socket "EXIT\n";

my @message = <$popbox/????>;
my $total = 0;
$total += -s foreach @message;
my $messages = @message;
cmp_ok($receiver->messages, '==', $messages, "Wrong number of messages");
cmp_ok($receiver->folderSize, '==', $total, "Wrong number of bytes");

my @id = $receiver->ids;
cmp_ok(scalar(@id), '==', scalar(@message), "Number of messages doesn't match");
is(join('',@id), join('',@message), "ID's don't match filenames");

$error = '';
foreach(@id)
{   my ($reported, $real) = ($receiver->messageSize($_),-s);
    $error .= "size $_ is not right: expected $real, got $reported\n"
     if $reported != $real;
}
ok(!$error, ($error || 'No errors with sizes'));

$error = '';
foreach(@id)
{   my $message = $receiver->message($_);
    open(my $handle, '<', $_);
    $error .= "content of $_ is not right\n"
     if join('', @$message) ne join('', <$handle>);
}
ok(!$error, $error || 'No errors with contents');

$receiver->deleted(1,@id);
ok($receiver->disconnect, 'Failed to properly disconnect from server');

@message = <$popbox/????>;
cmp_ok(scalar(@message) ,'==', 0, 'Did not remove messages at QUIT');
ok(rmdir($popbox), "Failed to remove $popbox directory: $!\n");

is(join('', <$server>), <<EOD, 'Statistics contain unexpected information');
1
APOP 1
DELE 4
EXIT 1
LIST 1
NOOP 8
QUIT 1
RETR 4
STAT 1
UIDL 1
EOD
