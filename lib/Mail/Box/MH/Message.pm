
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

=cut

#-------------------------------------------

=method seqnr [$integer]

The order of this message in the folder, counted from zero.  Do not
change the number (unless you understand the implications).

WARNING:  This sequence number has nothing to do with the message's
filename, which in case of MH folders are also numbers!  If you need
that one, use the M<File::Basename::basename()> of the filename.

=cut

# Purpose of doc is only the warning... no new implementation required.

#-------------------------------------------

=chapter DETAILS

=section Labels

=subsection The .mh_sequences file

Typically, the file which contains the labels is called C<.mh_sequences>.
The MH messages are numbered from C<1>.  As example content for
C<.mh_sequences>:

 cur: 93
 unseen: 32 35-56 67-80

To generalize labels on messages, two are treated specially:

=over 4

=item * cur

The C<cur> specifies the number of the message where the user stopped
reading mail from this folder at last access.  Internally in these
modules referred to as label C<current>.

=item * unseen

With C<unseen> is listed which message was never read.
This must be a mistake in the design of MH: it must be a source of
confusion.  People should never use labels with a negation in the
name:

 if($seen)           if(!$unseen)    #yuk!
 if(!$seen)          if($unseen)
 unless($seen)       unless($unseen) #yuk!

So: label C<unseen> is translated into C<seen> for internal use.

=back

=cut

1;
