
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

=method printStructure [$fh|undef],[$indent]
Print the structure of a message to the specified $fh or the
selected filehandle.  When explicitly C<undef> is specified as handle,
then the output will be returned as string.

The message's subject and the types of all composing parts are
displayed.

$indent specifies the initial indentation string: it is added in front
of each line. The $indent must contain at least one white-space.

=examples
 my $msg = ...;
 $msg->printStructure(\*OUTPUT);

 $msg->printStructure;

 my $struct = $msg->printStructure(undef);

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

    my $indent
      = @_==2                       ? pop
      : defined $_[0] && !ref $_[0] ? shift
      :                               '';

    my $fh      = @_ ? shift : select;

    my $buffer;   # only filled if filehandle==undef
    open $fh, '>:raw', \$buffer unless defined $fh;

    my $subject = $self->get('Subject') || '';
    $subject    = ": $subject" if length $subject;

    my $type    = $self->get('Content-Type', 0) || '';
    my $size    = $self->size;
    my $deleted = $self->label('deleted') ? ', deleted' : '';

    my $text    = "$indent$type$subject ($size bytes$deleted)\n";
    ref $fh eq 'GLOB' ? (print $fh $text) : $fh->print($text);

    my $body    = $self->body;
    my @parts
      = $body->isNested    ? ($body->nested)
      : $body->isMultipart ? $body->parts
      :                      ();

    $_->printStructure($fh, $indent.'   ')
        for @parts;

    $buffer;
}
    
=section Flags
=cut

1;
