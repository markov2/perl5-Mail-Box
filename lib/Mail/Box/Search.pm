#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::Search;
use parent 'Mail::Reporter';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error/ ];

#--------------------
=chapter NAME

Mail::Box::Search - select messages within a mail box

=chapter SYNOPSIS

  use Mail::Box::Manager;
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open('Inbox');

  my $filter = Mail::Box::Search::[something]->new;
  my @msgs   = $filter->search($folder, ...);
  if($filter->search($message)) {...}

=chapter DESCRIPTION

This C<Mail::Box::Search> class is the base class for various message scan
algorithms.  The selected messages can be labeled.  Boolean operations on
messages are supported.

Currently implemented searches:

=over 4

=item Mail::Box::Search::Grep
Match header or body against a regular expression in a UNIX C<grep> like
fashion.

=item C<Mail::Box::Search::SpamAssassin>
The original implementation supported only SpamAssassin 2.x, and therefore
this implementation was removed for Mail::Box 4.

=item C<Mail::Box::Search::IMAP>
Search an IMAP folder for special interface IMAP folders provide for it.
Implementation not completed.

=back

=chapter METHODS

=c_method new %options

Create a filter.

=option  binaries BOOLEAN
=default binaries <false>
Whether to include binary bodies in the search.

=option  decode BOOLEAN
=default decode <true>
Decode the messages before the search takes place.  Even plain text messages
can be encoded, for instance as C<quoted-printable>, which may disturb the
results.  However, decoding will slow-down the search.

=option  deliver undef|CODE|'DELETE'
=default deliver undef
The exact functionality of this parameter differs per search method, so
read the applicable man-page.  In any case undef means that details
are not collected for this search, which is the fastest search.

C<DELETE> will flag the message to be flagged for deletion.
You may also specify your own CODE reference.  With an reference
to an array, the information about the matches is collected as a list
of hashes, one hash per match.

=option  in 'HEAD'|'BODY'|'MESSAGE'
=default in C<'BODY'>
Where to look for the match.

=option  delayed BOOLEAN
=default delayed true
Include the delayed messages (which will be parsed) in the search.  If you
set this to false, you may find fewer hits.

=option  deleted BOOLEAN
=default deleted false
In most cases, you will not be interested in results which are
found in messages flagged to be deleted.  However, with this option
you can specify you want them to be searched too.

=option  label $label
=default label undef
Mark all selected messages with the specified label.  If this field is
not specified, the message will not get a label; C<search()> also returns
a LIST of selected messages.

=option  limit $number
=default limit C<0>
Limit the search to the specified $number of messages.  When the $number
is positive, the search starts at the first message in the folder or
thread.  A negative $number starts at the end of the folder.  If the limit
is set to zero, there is no limit.

=option  logical 'REPLACE'|'AND'|'OR'|'NOT'|'AND NOT'|'OR NOT'
=default logical C<'REPLACE'>

Only applicable in combination with a P<label>.
How to handle the existing labels.  In case of C<REPLACE>, messages
which already are carrying the label are stripped from their
selection (unless they match again).  With C<AND>, the message must
be selected by this search and already carry the label, otherwise the
label will not be set.  Specify C<OR> to have newly selected messages
added to the set of already selected messages.

C<NOT> is true for messages which do not fulfil the search.  The
details output will still contain the places where the match was
found, however those messages will complementary set of messages will
be labeled and returned.

=option  multiparts BOOLEAN
=default multiparts true
Are multiparts to be included in the search results?  Some MUA have
problems handling details received from the search.  When this flag
is turned off, the body of multiparts will be ignored.  The parts
search will include the preamble and epilogue.

=error search in BODY, HEAD or MESSAGE, not $what.
The P<in> option offers only three alternatives.

=error cannot search in header.
The search object does not implement M<inHead()>, and can therefore
not search a message header.

=error cannot search in body.
The search object does not implement M<inBody()>, and can therefore
not search a message body.

=error don't know how to deliver results in $what.
The search results cannot be delivered in the specific way, because that is
not a defined alternative.

=cut

sub init($)
{	my ($self, $args) = @_;

	$self->SUPER::init($args);

	my $in = $args->{in} || 'BODY';
	@$self{ qw/MBS_check_head MBS_check_body/ }
	  = $in eq 'BODY'    ? (0,1)
	  : $in eq 'HEAD'    ? (1,0)
	  : $in eq 'MESSAGE' ? (1,1)
	  :    error __x"search in BODY, HEAD or MESSAGE, not {what UNKNOWN}.", what => $in;

	! $self->{MBS_check_head} || $self->can('inHead') or error __x"cannot search in header.";
	! $self->{MBS_check_body} || $self->can('inBody') or error __x"cannot search in body.";

	my $deliver             = $args->{deliver};
	$self->{MBS_deliver}
	  = ref $deliver eq 'CODE' ? sub { $deliver->($self, $_[0]) }
	  : !defined $deliver      ? undef
	  : $deliver eq 'DELETE'   ? sub { $_[0]->{part}->toplevel->label(deleted => 1) }
	  :    error __x"don't know how to deliver results in {what UNKNOWN}.", what => $deliver;

	my $logic               = $args->{logical}  || 'REPLACE';
	$self->{MBS_negative}   = $logic =~ s/\s*NOT\s*$//;
	$self->{MBS_logical}    = $logic;

	$self->{MBS_label}      = $args->{label};
	$self->{MBS_binaries}   = $args->{binaries} || 0;
	$self->{MBS_limit}      = $args->{limit}    || 0;
	$self->{MBS_decode}     = $args->{decode}   || 1;
	$self->{MBS_no_deleted} = not $args->{deleted};
	$self->{MBS_delayed}    = defined $args->{delayed} ? $args->{delayed} : 1;
	$self->{MBS_multiparts} = defined $args->{multiparts} ? $args->{multiparts} : 1;

	$self;
}

#--------------------
=section Attributes

=method deliver
=method doMultiparts
=method parseDelayed
=method skipDeleted
=cut

sub deliver()      { $_[0]->{MBS_deliver} }
sub doMultiparts() { $_[0]->{MBS_multiparts} }
sub parseDelayed() { $_[0]->{MBS_delayed} }
sub skipDeleted()  { $_[0]->{MBS_no_deleted} }

#--------------------
=section Searching

=method search $folder|$thread|$message|ARRAY

Check which messages from the $folder (Mail::Box) match the
search parameters.  The matched messages are returned as list.  You
can also specify a $thread (a Mail::Box::Thread::Node), one single
$message (a Mail::Message), or an ARRAY of messages.

Sometimes we know how only one match is needed.  In this case, this
searching will stop at the first match.  For instance, when C<limit> is C<-1>
or C<1>, or when the search in done in scalar context.

=examples

  my $grep = Mail::Box::Search::Grep->new(
    match   => 'My Name Is Nobody',
    deliver => 'PRINT'
  );

  $grep->search($folder);

  my $message = $folder->message(3);
  $grep->search($message);

  my $thread  = $message->threadStart;
  $grep->search($thread);

=error expect messages to search, not $what.
=cut

sub search(@)
{	my ($self, $object) = @_;

	my $label         = $self->{MBS_label};
	my $limit         = $self->{MBS_limit};

	my @messages
	  = ref $object eq 'ARRAY'        ? @$object
	  : $object->isa('Mail::Box')     ? $object->messages
	  : $object->isa('Mail::Message') ? ($object)
	  : $object->isa('Mail::Box::Thread::Node') ? $object->threadMessages
	  :   error __x"expect messages to search, not {what UNKNOWN}.", what => $object;

	my $take = 0;
	   if($limit < 0) { $take = -$limit; @messages = reverse @messages }
	elsif($limit > 0) { $take = $limit }
	elsif(!defined $label && !wantarray && !$self->deliver) {$take = 1 }

	my $logic         = $self->{MBS_logical};
	my @selected;
	my $count = 0;

	foreach my $message (@messages)
	{	next if $self->skipDeleted && $message->isDeleted;
		next unless $self->parseDelayed || !$message->isDelayed;

		my $set = defined $label ? $message->label($label) : 0;

		my $selected
		  =  $set && $logic eq 'OR'  ? 1
		  : !$set && $logic eq 'AND' ? 0
		  : $self->{MBS_negative}    ? ! $self->searchPart($message)
		  :    $self->searchPart($message);

		$message->label($label => $selected) if defined $label;
		if($selected)
		{	push @selected, $message;
			$count++;
			last if $take && $count == $take;
		}
	}

	$limit < 0 ? reverse @selected : @selected;
}


=method searchPart $part
Search this message $part for matches.
=cut

sub searchPart($)
{	my ($self, $part) = @_;

	my $matched = 0;
	$matched  = $self->inHead($part, $part->head)
	if $self->{MBS_check_head};

	return $matched unless $self->{MBS_check_body};
	return $matched if $matched && !$self->deliver;

	my $body  = $part->body;
	my @bodies;

	# Handle multipart parts.

	if($body->isMultipart)
	{	$self->doMultiparts or return $matched;

		@bodies = ($body->preamble, $body->epilogue);

		foreach my $piece (grep defined, $body->parts)
		{	next if $piece->isDelayed && ! $self->parseDelayed;

			$matched += $self->searchPart($piece);
			return $matched if $matched && !$self->deliver;
		}
	}
	elsif($body->isNested)
	{	$self->doMultiparts or return $matched;
		$matched += $self->searchPart($body->nested);
	}
	else
	{	@bodies = ($body);
	}

	# Handle normal bodies.

	foreach (grep defined, @bodies)
	{	next if !$self->{MBS_binaries} && $_->isBinary;
		my $body   = $self->{MBS_decode} ? $_->decoded : $_;
		my $inbody = $self->inBody($part, $body);
		$matched  += $inbody;
	}

	$matched;
}

=method inHead $part, $head
Tests whether header contains the requesting information.  See the
specific search module for its parameters.
=cut

sub inHead(@) { $_[0]->notImplemented }

=method inBody $part, $body
Tests whether body contains the requesting information.  See the
specific search module for its parameters.
=cut

sub inBody(@) { $_[0]->notImplemented }

#--------------------
=section The Results

=method printMatch [$fh], HASH
Print the information about the match (see M<new(deliver)>) in some
understandable way.  If no file handle $fh is specified, the output will
go to the selected filehandle (see C<perldoc -f select>).
=cut

sub printMatch($) { $_[0]->notImplemented }

1;
