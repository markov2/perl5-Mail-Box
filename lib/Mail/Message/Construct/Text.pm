
use strict;

package Mail::Message;

use IO::Lines;

=chapter NAME

Mail::Message::Construct::Text - capture a Mail::Message as text

=chapter SYNOPSIS

 my $text = $msg->string;
 my $text = "$msg";   # via overload

 my @text = $msg->lines;
 my @text = @$lines;  # via overload

 my $fh   = $msg->file;
 my $line = <$fh>;

 $msg->printStructure;

=chapter DESCRIPTION

Complex functionality on M<Mail::Message> objects is implemented in
different files which are autoloaded.  This file implements the
functionality related to creating message replies.

=chapter METHODS

=section The whole message as text

=method string
Returns the whole message as string.

=cut

sub string()
{   my $self = shift;
    $self->head->string . $self->body->string;
}

#------------------------------------------

=method lines

Returns the whole message as set of lines.  In LIST context, copies of the
lines are returned.  In SCALAR context, a reference to an array of lines
is returned.

=cut

sub lines()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    wantarray ? @lines : \@lines;
}

#------------------------------------------

=method file
Returns the message as file-handle.

=cut

sub file()
{   my $self = shift;
    my @lines;
    my $file = IO::Lines->new(\@lines);
    $self->print($file);
    $file->seek(0,0);
    $file;
}

#------------------------------------------

=method printStructure [FILEHANDLE][, INDENT]

Print the structure of a message to the selected filehandle.
The message's subject and the types of all composing parts are
displayed.

INDENT specifies the initial indentation string: it is added in
front of each line, and SHALL end with a blank, if specified.

=examples

 my $msg = ...;
 $msg->printStructure(\*OUTPUT);
 $msg->printStructure;

 # Possible output for one message:
 multipart/mixed: forwarded message from Pietje Puk (1550 bytes)
    text/plain (164 bytes)
    message/rfc822 (1043 bytes)
       multipart/alternative: A multipart alternative (942 bytes)
          text/plain (148 bytes, deleted)
          text/html (358 bytes)

=cut

sub printStructure(;$$)
{   my $self    = shift;
    my $indent  = @_ && !ref $_[-1] && substr($_[-1], -1, 1) eq ' ' ? pop : '';
    my $fh      = @_ ? shift : select;

    my $subject = $self->get('Subject') || '';
    $subject    = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type') || '';
    my $size    = $self->size;
    my $deleted = $self->label('deleted') ? ', deleted' : '';

    my $text    = "$indent$type$subject ($size bytes$deleted)\n";
    ref $fh eq 'GLOB' ? (print $fh $text) : $fh->print($text);

    my $body    = $self->body;
    my @parts
      = $body->isMultipart ? $body->parts
      : $body->isNested    ? ($body->nested)
      :                      ();

    $_->printStructure($fh, $indent.'   ') foreach @parts;
}
    
1;
