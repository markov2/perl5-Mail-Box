#!/usr/bin/perl

# Demonstration on sending simple messages.
#
# This code can be used and modified without restriction.
# Mark Overmeer, <mailbox@overmeer.net>, 20 nov 2001

use warnings;
use strict;
use lib '..', '.';

use Mail::Box;

#
# Get the command line arguments.
#

die "Usage: $0 email-address\n"
    unless @ARGV==1;

my $email = shift @ARGV;

#
# Create a simple message
#

my $message = Mail::Message->build
 ( From    => 'me@localhost.com'
 , To      => $email
 , Subject => 'A sunny day'
 , Cc      => 'NINJA <ninja>, Mark Overmeer <markov>'

 , data => <<'TEXT'
This is an automatically generated message.
I hope you have a nice day.
TEXT
 );

#
# Transmit the message, leaving the decission how over to the
# Mail::Transmit package.
#

warn "Sending returned error $!\n"
   unless $message->send(via => 'smtp', trace => 'NOTICE', debug => 1);

#$message->send(via => 'sendmail');
