
use strict;
use warnings;

package Mail::Message::Convert::MimeEntity;
use base 'Mail::Message::Convert';

use MIME::Entity;
use MIME::Parser;
use Mail::Message;

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

=method export $message, [$parser]
Returns a new L<MIME::Entity> message object based on the
information from the $message, which is a M<Mail::Message> object.

You may want to supply your own $parser, which is a M<MIME::Parser>
object, to change the parser flags.  Without a $parser object, one
is created for you, with all the default settings.

If C<undef> is passed, in place of a $message, then an empty list is
returned.  When the parsing failes, then L<MIME::Parser> throws an
exception.

=examples

 my $convert = Mail::Message::Convert::MimeEntity->new;
 my Mail::Message $msg  = M<Mail::Message>->new;
 my L<MIME::Entity>  $copy = $convert->export($msg);

=cut

sub export($$;$)
{   my ($self, $message, $parser) = @_;
    return () unless defined $message;

    $self->log(ERROR =>
       "Export message must be a Mail::Message, but is a ".ref($message)."."),
           return
              unless $message->isa('Mail::Message');

    $parser ||= MIME::Parser->new;
    $parser->parse($message->file);
}

=method from $mime_object
Returns a new M<Mail::Message> object based on the information from
the specified L<MIME::Entity>.  If the conversion fails, the C<undef>
is returned.  If C<undef> is passed in place of an OBJECT, then an
empty list is returned.

=examples

 my $convert = Mail::Message::Convert::MimeEntity->new;
 my MIME::Entity  $msg  = M<MIME::Entity>->new;
 my M<Mail::Message> $copy = $convert->from($msg);

=error Converting from MIME::Entity but got a $type, return
=cut

sub from($)
{   my ($self, $mime_ent) = @_;
    return () unless defined $mime_ent;

    $self->log(ERROR =>
       'Converting from MIME::Entity but got a '.ref($mime_ent).'.'), return
            unless $mime_ent->isa('MIME::Entity');

    Mail::Message->read($mime_ent->as_string);
}

1;
