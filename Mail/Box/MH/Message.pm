
use strict;
use warnings;

package Mail::Box::MH::Message;
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;

=head1 NAME

Mail::Box::MH::Message - one message in a MH-folder

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A Mail::Box::MH::Message represents one message in an MH-folder. Each
message is stored in a separate file.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=cut

#-------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

=method seqnr [INTEGER]

The order of this message in the folder, counted from zero.  Do not
change the number (unless you understand the implications).

WARNING:  This sequence number has nothing to do with the message's
filename, which in case of MH folders are also numbers!  If you need
that one, use C<< basename $msg->filename >>.

=cut

1;
