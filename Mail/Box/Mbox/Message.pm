
use strict;
package Mail::Box::Mbox::Message;
use base 'Mail::Box::File::Message';

=head1 NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=head1 SYNOPSIS

 my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=head1 DESCRIPTION

Maintain one message in an Mbox folder.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=cut

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

=head2 The Header

=cut

#-------------------------------------------

=head2 Labels

=cut

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

1;
