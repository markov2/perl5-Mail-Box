
use strict;
use warnings;

package Mail::Message::Convert::MailInternet;
use base 'Mail::Message::Convert';

use Mail::Internet;
use Mail::Header;
use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;

use Carp;

our $VERSION = 2.007;

=head1 NAME

Mail::Message::Convert::MailInternet - translate Mail::Message to Mail::Internet vv

=head1 CLASS HIERARCHY

 Mail::Message::Convert::MailInternet
 is a Mail::Message::Convert
 is a Mail::Reporter

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

The C<Mail::Internet> class of message is very popular for all
kinds of message applications written in Perl.  However, the
format was developed when e-mail messages where still small and
attachments where rare; C<Mail::Message> is much more flexible in
this respect.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Convert::MailInternet> objects:

   MR errors                            MR new OPTIONS
  MMC export MESSAGE, OPTIONS           MR report [LEVEL]
  MMC from OBJECT, OPTIONS              MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMC = L<Mail::Message::Convert>

=head1 METHODS

=over 4

=cut

#------------------------------------------

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

my @pref_order = qw/From To Cc Subject Date In-Reply-To References
    Content-Type Lines Content-Length/;

sub from($@)
{   my ($thing, $mi) = (shift, shift);

    croak "Converting from Mail::Internet but got a ".ref($mi).'.'
        unless $mi->isa('Mail::Internet');

    my $head = Mail::Message::Head::Complete->new;
    my $body = Mail::Message::Body::Lines->new(data => [ @{$mi->body} ]);

    my $mi_head = $mi->head;

    # The tags of Mail::Header are unordered, but we prefer some ordening.
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

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.007.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
