
use strict;
use warnings;

package Mail::Message::Convert::MailInternet;
use base 'Mail::Message::Convert';

use Mail::Internet;
use Mail::Header;
use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;

use Carp;

our $VERSION = 2.018;

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

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Convert> (MMC).

The general methods for C<Mail::Message::Convert::MailInternet> objects:

   MR errors                            MR report [LEVEL]
      export MESSAGE, OPTIONS           MR reportAll [LEVEL]
      from OBJECT, OPTIONS              MR trace [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR warnings
      new OPTIONS

The extra methods for extension writers:

   MR AUTOLOAD                          MR logSettings
   MR DESTROY                           MR notImplemented
   MR inGlobalDestruction              MMC selectedFields HEAD
   MR logPriority LEVEL

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTIONS         DESCRIBED IN           DEFAULT
 log             Mail::Reporter         'WARNINGS'
 trace           Mail::Reporter         'WARNINGS'

=cut

#------------------------------------------

=item export MESSAGE, OPTIONS

Returns a new message object based on the information from
a C<Mail::Message> object.  The MESSAGE specified is an
instance of a C<Mail::Message>.

Examples:

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

=item from OBJECT, OPTIONS

Returns a new C<Mail::Message> object based on the information from
an message-type which is strange to the C<Mail::Box> set of modules.

Examples:

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

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.018.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
