
use strict;
use warnings;

package Mail::Server;
use base 'Mail::Reporter';

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
=item * M<Mail::Server::IMAP4>
Partial IMAP4 implementation.
=back

=chapter METHODS

=chapter DETAILS

=cut

1;
