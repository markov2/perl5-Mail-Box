
use strict;
use warnings;

package Mail::Message::Convert::MimeEntity;
use base 'Mail::Message::Convert';

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use MIME::Entity;
use MIME::Body;
use Carp;

=chapter NAME

Mail::Message::Convert::MimeEntity - translate Mail::Message to MIME::Entity vv

=chapter SYNOPSIS

 use Mail::Message::Convert::MimeEntity;
 my $convert = Mail::Message::Convert::MimeEntity->new;

 my Mail::Message $msg    = M<Mail::Message>->new;
 my MIME::Entity  $entity = $convert->export($msg);

 my MIME::Entity  $entity = M<MIME::Entity>->new;
 my Mail::Message $msg    = $convert->from($entity);

 use Mail::Box::Manager;
 my $mgr     = M<Mail::Box::Manager>->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($entity);

=chapter DESCRIPTION

The M<MIME::Entity> extends M<Mail::Internet> message with multiparts
and more methods.  The M<Mail::Message> objects are more flexible
in how the message parts are stored, and uses separate header and body
objects.

=chapter METHODS

=section Converting

=method export MESSAGE, OPTIONS

Returns a new message object based on the information from
a M<Mail::Message> object.  The MESSAGE specified is an
instance of a Mail::Message.

=examples

 my $convert = Mail::Message::Convert::MimeEntity->new;
 my Mail::Message $msg  = M<Mail::Message>->new;
 my M<MIME::Entity>  $copy = $convert->export($msg);

=cut

sub export($$)
{   my ($self, $message) = @_;

    croak "Export message must be a Mail::Message, but is a ".ref($message)."."
        unless $message->isa('Mail::Message');

    my $me   = MIME::Entity->new;
    my $body = $message->body;

    if($body->isMultipart)
    {   my $preamble = $body->preamble->lines;
        $me->preamble($preamble) if $preamble;

        $me->add_part($self->export($_))
            foreach $body->parts;

        my $epilogue = $body->epilogue->lines;
        $me->epilogue($epilogue) if $epilogue;
    }
    elsif(my $lines = $body->lines)
    {   $me->bodyhandle(MIME::Body::InCore->new($lines));
    }

    my $me_head = MIME::Head->new;
    my $head    = $message->head;
    foreach my $name ($head->names)
    {   $me_head->add(undef, $_->string."\n")
            foreach $head->get($name);
    }

    $me->head($me_head);

    $me->sync_headers(Length => 'COMPUTE');
    $me;
}

#------------------------------------------

=method from OBJECT, [CONTAINER]

Returns a new M<Mail::Message> object based on the information from
an message-type which is foreign to the Mail::Box set of modules.

=examples

 my $convert = Mail::Message::Convert::MimeEntity->new;
 my MIME::Entity  $msg  = M<MIME::Entity>->new;
 my M<Mail::Message> $copy = $convert->from($msg);

=cut

sub from($;$)
{   my ($self, $me, $container) = @_;

    croak "Converting from MIME::Entity but got a ".ref($me).'.'
        unless $me->isa('MIME::Entity');

    # The order of the headers for MIME::Entity is a mess, so it
    # is reordered a little.

    my $head    = Mail::Message::Head::Complete->new;
    my $me_head = $me->head;

    my (%tags, @tags);
    $tags{$_}++ foreach $me_head->tags;
    delete $tags{$_} && push @tags, $_
       foreach qw/From To Subject/;

    foreach my $name (@tags, keys %tags)
    {   $head->add($name, $_) foreach $me_head->get($name);
    }

    my $message = defined $container
      ? Mail::Message::Part->new(head => $head, container => $container)
      : Mail::Message->new(head => $head);

    if($me->is_multipart)
    {   my $preamble = $me->preamble;
        $preamble    = Mail::Message::Body::Lines->new(data => $preamble)
            if defined $preamble;

        my @parts    = map {$self->from($_, $message)} $me->parts;

        my $epilogue = $me->epilogue;
        $epilogue    = Mail::Message::Body::Lines->new(data => $epilogue)
            if defined $epilogue;

        my $body     = Mail::Message::Body::Multipart->new
          ( preamble => $preamble
          , parts    => \@parts
          , epilogue => $epilogue
          );

        $message->body($body) if defined $body;
    }
    else
    {   my $body = Mail::Message::Body::Lines->new(data => \@{$me->body} );
        $message->body($body) if defined $body;
    }

    $message;
}

#------------------------------------------

1;
