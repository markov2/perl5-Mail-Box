#!/usr/bin/perl
#
# Test conversions between Mail::Message and MIME::Entity
#

use Test;
use strict;
use warnings;

use lib qw(. t);

use Tools;
use Mail::Message;

BEGIN
{   eval {require MIME::Entity};
    if($@)
    {   warn "requires MIME::Entity.\n";
        plan tests => 0;
        exit 0;
    }

    require Mail::Message::Convert::MimeEntity;
    plan tests => 28;
}

my $me   = MIME::Entity->build
 ( From          => 'mailtools@overmeer.net'
 , To            => 'the users'
 , Subject       => 'use Mail::Box'
 , 'In-Reply-To' => '<023984hjlur29420@sruoiu.nl>'
 , 'X-Again'     => 'repeating header'
 , 'X-Again'     => 'repeating header again'
 , 'X-Again'     => 'repeating header and again'
 , Data          => [ <DATA> ]
 );

ok($me);

my $convert = Mail::Message::Convert::MimeEntity->new;
ok($convert);

#
# Convert MIME::Entity to Mail::Message
#

my $msg = $convert->from($me);
ok($msg);

my $head = $msg->head;
ok($head);

# MIME::Entity makes a mess on the headers: not usefull to test the
# order of the returned.

my @from  = $head->get('From');
ok(@from==1);

my @again = $head->get('X-again');
#  ok(@again==3);   # Should be 3, but bug in MIME::Entity
ok(@again==1);      # Wrong, but to check improvements in ME

my $body  = $msg->body;
ok($body);

my @lines = $body->lines;
ok(@lines==6);
ok($lines[-1] eq "use it anymore!\n");

#
# Convert message back to a MIME::Entity
#

my $back = $convert->export($msg);
ok(defined $back);
$head    = $back->head;

ok($head->get('to') eq "the users\n");

@from    = $head->get('from');
ok(@from==1);

@again   = $head->get('x-again');
ok(@again==1);

$body = $back->bodyhandle;
ok($body);

@lines = $body->as_lines;
ok(@lines==6);

#
# and now: MULTIPARTS!  Convert MIME::Entity to Mail::Message
#

$me = MIME::Entity->build
 ( From => 'me', To => 'you', Type => 'multipart/mixed'
 , Subject => 'Test mp conv'
 , Data => [ "Some\n", "Lines\n" ]
 );
$me->preamble( [ "Pre1\n", "Pre2\n" ]);
$me->attach(Data => [ "First part\n" ] );
$me->attach(Data => [ "Second part\n" ] );
$me->epilogue( [ "Epi1\n", "Epi2\n" ]);

$msg = $convert->from($me);
ok(defined $msg);
ok($msg->isMultipart);

my @parts = $msg->parts;
ok(@parts==2);
ok($msg->isa('Mail::Message'));
ok($parts[0]->isa('Mail::Message::Part'));
ok($parts[1]->isa('Mail::Message::Part'));

$body = $msg->body;
ok($body->preamble->nrLines==2);
ok($body->epilogue->nrLines==2);
#$msg->print;

#
# Convert MULTIPART message back to a MIME::Entity
#

$me = $convert->export($msg);
#$me->print;
ok($me->isa('MIME::Entity'));
ok($me->is_multipart);
@parts = $me->parts;
ok(@parts==2);
ok($parts[0]->isa('MIME::Entity'));
ok($parts[1]->isa('MIME::Entity'));

1;

__DATA__
MIME::Entity is written by Eriq, and extends Mail::Internet with many
new capabilities, like multipart bodies.  Actually, although it says
to extend, it more or less reimplements most methods and conflicts
with the other.  Even the Mail::Internet constructor does not work:
only the build() can be used to safely construct a message.  Do not
use it anymore!
