
use strict;
use warnings;

package Mail::Box::MH::Message;
use base 'Mail::Box::Dir::Message';

use File::Copy;
use Carp;

=chapter NAME

Mail::Box::MH::Message - one message in an MH-folder

=chapter SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::MH::Message> represents one message in an
M<Mail::Box::MH> folder . Each message is stored in a separate file,
as for all M<Mail::Box::Dir> folder types.

=chapter METHODS

=method seqnr [INTEGER]

The order of this message in the folder, counted from zero.  Do not
change the number (unless you understand the implications).

WARNING:  This sequence number has nothing to do with the message's
filename, which in case of MH folders are also numbers!  If you need
that one, use the M<File::Basename::basename()> of the filename.

=cut

# implementation in Mail::Box::Message.  It is only "helpful" text.

1;
