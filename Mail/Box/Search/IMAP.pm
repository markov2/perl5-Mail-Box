
package Mail::Box::Search::IMAP;
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

#-------------------------------------------

=chapter NAME

Mail::Box::Search::IMAP - select messages within a IMAP folder

=chapter SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open('imap4:Inbox');

 my $filter = Mail::Box::Search::IMAP->new
    (  ...to be defined...
    );

 my @msgs   = $filter->search($folder);
 if($filter->search($message)) {...}

=chapter DESCRIPTION

THIS PACKAGES IS NOT IMPLEMENTED YET: it waits for
M<Mail::Transport::IMAP4> to be available.

=chapter METHODS

=c_method new OPTIONS

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->notImplemented;
}

#-------------------------------------------

1;
