
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

our $VERSION = 2.007;

=head1 NAME

Mail::Message::Convert::MimeEntity - translate Mail::Message to MIME::Entity vv

=head1 CLASS HIERARCHY

 Mail::Message::Convert::MimeEntity
 is a Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::MimeEntity;
 my $convert = Mail::Message::Convert::MimeEntity->new;

 my Mail::Message $msg    = Mail::Message->new;
 my MIME::Entity  $entity = $convert->export($msg);

 my MIME::Entity  $entity = MIME::Entity->new;
 my Mail::Message $msg    = $convert->from($entity);

 use Mail::Box::Manager;
 my $mgr     = Mail::Box::Manager->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($entity);

=head1 DESCRIPTION

The C<MIME::Entity> extends C<Mail::Internet> message with multiparts
and more methods.  The C<Mail::Message> objects are more flexible
in how the message parts are stored, and uses separate header and body
objects.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Convert::MimeEntity> objects:

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

sub export($$)
{   my ($self, $message) = @_;

    croak "Export message must be a Mail::Message, but is a ".ref($message)."."
        unless $message->isa('Mail::Message');

    my $me   = MIME::Entity->new;
    my $body = $message->body;

    if($message->isMultipart)
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
    {   $me_head->add(undef, $_->toString."\n")
            foreach $head->get($name);
    }

    $me->head($me_head);

    $me->sync_headers(Length => 'COMPUTE');
    $me;
}

#------------------------------------------

sub from($;$)
{   my ($self, $me, $parent) = @_;

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

    my $message = defined $parent
      ? Mail::Message::Part->new(head => $head, parent => $parent)
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
