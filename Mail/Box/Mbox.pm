
use strict;
package Mail::Box::Mbox;
use base 'Mail::Box::File';

use Mail::Box::Mbox::Message;

=head1 NAME

Mail::Box::Mbox - handle folders in Mbox format

=head1 SYNOPSIS

 use Mail::Box::Mbox;
 my $folder = Mail::Box::Mbox->new(folder => $ENV{MAIL}, ...);

=head1 DESCRIPTION

This documentation describes how Mbox mailboxes work, and also describes
what you can do with the Mbox folder object Mail::Box::Mbox.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=default message_type 'Mail::Box::Mbox::Message'

=cut

#-------------------------------------------

=head2 Opening folders

=cut

#-------------------------------------------

=head2 On open folders

=cut

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

1;
