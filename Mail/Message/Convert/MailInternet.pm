
use strict;
use warnings;

package Mail::Message::Convert::MailInternet;
use base 'Mail::Message::Convert';

use Mail::Internet;
use Mail::Header;
use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;

use Carp;

=head1 NAME

Mail::Message::Convert::MailInternet - translate Mail::Message to Mail::Internet vv

=head1 SYNOPSIS

 use Mail::Message::Convert::MailInternet;
 my $convert = Mail::Message::Convert::MailInternet->new;

 my Mail::Message  $msg    = Mail::Message->new;
 my Mail::Internet $intern = $convert->export($msg);

 my Mail::Internet $intern = Mail::Internet->new;
 my Mail::Message  $msg    = $convert->from($intern);

 use Mail::Box::Manager;
 my $mgr     = Mail::Box::Manager->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($intern);

=head1 DESCRIPTION

The Mail::Internet class of message is very popular for all
kinds of message applications written in Perl.  However, the
format was developed when e-mail messages where still small and
attachments where rare; Mail::Message is much more flexible in
this respect.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=cut

#------------------------------------------

=head2 Converting

=cut

#------------------------------------------

=method export MESSAGE, OPTIONS

Returns a new message object based on the information from
a Mail::Message object.  The MESSAGE specified is an
instance of a Mail::Message.

=examples

 my $convert = Mail::Message::Convert::MailInternet->new;
 my Mail::Message  $msg   = Mail::Message->new;
 my Mail::Internet $copy  = $convert->export($msg);

=cut

sub export($@)
{   my ($thing, $message) = (shift, shift);

    croak "Export message must be a Mail::Message, but is a ".ref($message)."."
        unless $message->isa('Mail::Message');

    my $mi_head = Mail::Header->new;

    my $head    = $message->head;
    foreach my $name ($head->names)
    {   $mi_head->add(undef, $_->toString)
            foreach $head->get($name);
    }

    Mail::Internet->new
     ( Header => $mi_head
     , Body   => [ $message->body->lines ]
     , @_
     );
}

#------------------------------------------

=method from OBJECT, OPTIONS

Returns a new Mail::Message object based on the information from
an message-type which is strange to the Mail::Box set of modules.

=examples

 my $convert = Mail::Message::Convert::MailInternet->new;
 my Mail::Internet $msg  = Mail::Internet->new;
 my Mail::Message  $copy = $convert->from($msg);

=cut

my @pref_order = qw/From To Cc Subject Date In-Reply-To References
    Content-Type Lines Content-Length/;

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
