
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::File::Message';

=chapter NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=chapter SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=chapter DESCRIPTION

Maintain one message in an M<Mail::Box::Mbox> folder.

=chapter METHODS

=cut

1;
