
package Mail::Box::Search::IMAP;
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

#-------------------------------------------

=head1 NAME

Mail::Box::Search::IMAP - select messages within a IMAP folder

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open('imap4:Inbox');

 my $filter = Mail::Box::Search::IMAP->new
    (  ...to be defined...
    );

 my @msgs   = $filter->search($folder);
 if($filter->search($message)) {...}

=head1 DESCRIPTION

THIS PACKAGES IS NOT IMPLEMENTED YET: it waits for Mail::Transport::IMAP4
to be available.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=c_method new OPTIONS

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

=head2 Searching

=cut

#-------------------------------------------

=head2 The Results

=cut

#-------------------------------------------

1;
