#!/usr/bin/perl
#
# Test the processing of a message header, in this case purely the reading
# from a file.
#

use Test::More;
use strict;
use warnings;

use lib qw(. t);

use Mail::Message::Head;
use Mail::Box::Parser::Perl;
use Tools;

BEGIN { plan tests => 15 }

my $h = Mail::Message::Head->new;
ok(defined $h);

my $parser = Mail::Box::Parser::Perl->new(filename => $src);
ok($parser);

my $head = Mail::Message::Head->new;
ok(defined $head);
ok(! $head);  # no lines yet

$parser->pushSeparator('From ');
my ($where, $sep) = $parser->readSeparator;
ok($sep);
cmp_ok($where, "==", 0);
like($sep , qr/^From mag.*2000$/);

$head->read($parser);
ok($head);  # now has lines
cmp_ok($head->names, "==", 20);
is($head->get('subject'), 'Re: File Conversion From HTML to PS and TIFF');

my @received = $head->get('received');
cmp_ok(@received, "==", 5);

my $received = $head->get('received');  #last
ok(defined $received);
is($received->name, 'received');
my $recb = "(from majordomo\@localhost)\tby unca-don.wizards.dupont.com (8.9.3/8.9.3) id PAA29389\tfor magick-outgoing";

is($received->body, $recb);
is($received->comment, 'Wed, 9 Feb 2000 15:38:42 -0500 (EST)');

