#!/usr/bin/perl

# Demonstration on how to create a reply based on some message in
# some folder.
#
# Usage:
#      ./reply.pl folder messagenr [signaturefile]
#
# This code can be used and modified without restriction.
# Mark Overmeer, <mailbox@overmeer.net>, 9 nov 2001

use warnings;
use strict;
use lib '..', '.';

use Mail::Box::Manager 2.00;
use Mail::Message::Body::Lines;
use Mail::Message::Construct;

#
# Get the command line arguments.
#

die "Usage: $0 folderfile messagenr [signaturefile]\n"
    unless @ARGV==3 || @ARGV==2;

my ($filename, $msgnr, $sigfile) = @ARGV;

#
# Open the folder
#

my $mgr    = Mail::Box::Manager->new;

my $folder = $mgr->open
   ( $filename
   , lazy_extract => 'ALWAYS'   # never take the body unless needed
   );                           #  which saves memory and time.

die "Cannot open $filename: $!\n"
    unless defined $folder;

#
# Get the message to reply to
#

die "There are only ",scalar $folder->messages, " messages in $filename.\n"
   if $msgnr > $folder->messages;

my $orig = $folder->message($msgnr);
$folder->close;


#
# Create the reply prelude.
# The default only produces the replyPrelude line, but we extend it
# a little.
#

my @prelude = split /(?<=\n)/, <<'PRELUDE';
Dear friend,

This automatically produced message is just a reply on yours.  Please
do not be disturbed.  Best wishes, Me, myself, and I.

PRELUDE

push @prelude, $orig->quotePrelude($orig->get('From'));   # The usual quote line.

my $prelude = Mail::Message::Body::Lines->new(data => \@prelude);

#
# Create a new signature
# The postlude can contain more than only the signature.
#

my $postlude;
if(defined $sigfile)
{   open SIG, '<', $sigfile
        or die "Cannot read signature from $sigfile: $!\n";

    $postlude = Mail::Message::Body::Lines->new(data => [ <SIG> ]);
    close SIG;
}
else
{   $postlude = Mail::Message::Body::Lines->new(data => <<SIG);
--
This is the default signature.
Don't forget the double dash to start it!
SIG
}


#
# Create reply
# The original signature is stripped, the message is quoted, and a
# new signature is added.
#

my $reply = $orig->reply
 ( prelude  => $prelude
 , postlude => $postlude
 );


# And now send the message... or

$reply->print;
