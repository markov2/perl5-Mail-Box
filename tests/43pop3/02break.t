use Test::More tests => 11;
use File::Copy;

BEGIN { use_ok('Mail::Transport::POP3') }

my $serverscript = '43pop3/server';
my $original     = '43pop3/original';
my $popbox       = '43pop3/popbox';

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
print $socket "EXIT\n"; # make server exit on QUIT

$receiver->message($_) foreach $receiver->ids;
$receiver->deleteFetched;

print $socket "BREAK\n"; # force breaking of connection
ok($receiver->disconnect, 'Failed to properly disconnect from server');

my @message = <$popbox/????>;
cmp_ok(scalar(@message) ,'==', 0, 'Did not remove messages at QUIT');
ok(rmdir($popbox), "Failed to remove $popbox directory: $!\n");

is(join('', <$server>), <<EOD, 'Statistics contain unexpected information');
2
APOP 2
BREAK 1
DELE 4
EXIT 1
NOOP 6
QUIT 1
RETR 4
STAT 2
UIDL 2
EOD
