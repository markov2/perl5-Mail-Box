#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Server;
use parent 'Mail::Reporter';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw// ];

#--------------------
=chapter NAME

Mail::Server - Base class for email servers in MailBox

=chapter SYNOPSIS

  my $server = Mail::Server::IMAP4->new($msg);
  my $server = Mail::Server::POP3->new($msg);

=chapter DESCRIPTION

This module is a place-holder, logical in the class hierarchy.  On the
moment, no full server has been implemented, but some parts of IMAP4
exist.

Servers:

=over 4
=item * Mail::Server::IMAP4
Partial IMAP4 implementation.
=back

=chapter METHODS

=chapter DETAILS

=cut

1;
