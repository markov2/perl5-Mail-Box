
use strict;
use warnings;

package Mail::Message::Convert::MailInternet;
use base 'Mail::Message::Convert';

use Mail::Internet;
use Mail::Header;
use Mail::Message;
use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;

use Carp;

=chapter NAME

Mail::Message::Convert::MailInternet - translate Mail::Message to Mail::Internet vv

=chapter SYNOPSIS

 use Mail::Message::Convert::MailInternet;
 my $convert = Mail::Message::Convert::MailInternet->new;

 my Mail::Message  $msg    = M<Mail::Message>->new;
 my Mail::Internet $intern = $convert->export($msg);

 my Mail::Internet $intern = M<Mail::Internet>->new;
 my Mail::Message  $msg    = $convert->from($intern);

 use M<Mail::Box::Manager>;
 my $mgr     = Mail::Box::Manager->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($intern);

=chapter DESCRIPTION

The M<Mail::Internet> class of messages is very popular for all
kinds of message applications written in Perl.  However, the
format was developed when e-mail messages where still small and
attachments where rare; Mail::Message is much more flexible in
this respect.

=chapter METHODS

=section Converting

=method export $message, %options

Returns a new message object based on the information from
a M<Mail::Message> object.  The $message specified is an
instance of a Mail::Message.

=examples

 my $convert = Mail::Message::Convert::MailInternet->new;
 my Mail::Message  $msg   = M<Mail::Message>->new;
 my M<Mail::Internet> $copy  = $convert->export($msg);

=cut

sub export($@)
{   my ($thing, $message) = (shift, shift);

    croak "Export message must be a Mail::Message, but is a ".ref($message)."."
        unless $message->isa('Mail::Message');

    my $mi_head = Mail::Header->new;

    my $head    = $message->head;
    foreach my $field ($head->orderedFields)
    {   $mi_head->add($field->Name, scalar $field->foldedBody);
    }

    Mail::Internet->new
     ( Header => $mi_head
     , Body   => [ $message->body->lines ]
     , @_
     );
}

#------------------------------------------

=method from $object, %options

Returns a new M<Mail::Message> object based on the information
from a M<Mail::Internet> object. 

=examples
 my $convert = Mail::Message::Convert::MailInternet->new;
 my Mail::Internet $msg  = M<Mail::Internet>->new;
 my M<Mail::Message>  $copy = $convert->from($msg);

=cut

my @pref_order = qw/From To Cc Subject Date In-Reply-To References
    Content-Type/;

sub from($@)
{   my ($thing, $mi) = (shift, shift);

    croak "Converting from Mail::Internet but got a ".ref($mi).'.'
        unless $mi->isa('Mail::Internet');

    my $head = Mail::Message::Head::Complete->new;
    my $body = Mail::Message::Body::Lines->new(data => [ @{$mi->body} ]);

    my $mi_head = $mi->head;

    # The tags of Mail::Header are unordered, but we prefer some ordering.
    my %tags = map {lc $_ => ucfirst $_} $mi_head->tags;
    my @tags;
    foreach (@pref_order)
    {   push @tags, $_ if delete $tags{lc $_};
    }
    push @tags, sort values %tags;
    
    foreach my $name (@tags)
    {   $head->add($name, $_)
            foreach $mi_head->get($name);
    }

    Mail::Message->new(head => $head, body => $body, @_);
}

#------------------------------------------

1;
