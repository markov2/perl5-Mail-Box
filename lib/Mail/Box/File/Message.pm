
use strict;
package Mail::Box::File::Message;
use base 'Mail::Box::Message';

use List::Util   qw/sum/;

=chapter NAME

Mail::Box::File::Message - one message in a Mbox folder

=chapter SYNOPSIS

 my $folder  = new Mail::Box::File folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=chapter DESCRIPTION

Maintain one message in an file based folder, any M<Mail::Box::File>
extension.

=chapter METHODS

=c_method new %options
Messages in file-based folders use the following options for creation:

=option  from_line STRING
=default from_line undef
The line which begins each message in the file. Some people detest
this line, but this is just how things were invented...

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->fromLine($args->{from_line})
        if exists $args->{from_line};

    $self;
}

sub coerce($)
{   my ($self, $message) = @_;
    return $message if $message->isa(__PACKAGE__);
    $self->SUPER::coerce($message)->labelsToStatus;
}

=method write [$fh]
Write one message to a file handle.  It is the message including the
leading 'From ' line and trailing blank.  The From-line may interfere
with lines in the body: those lines are escaped with an extra '>'.

=examples
 $msg->write(\*FILE);    # print the message with encaps to FILE
 $msg->write;            # message with encaps to selected filehandle
 $msg->print(\*FILE);    # the message without encaps.
=cut

sub write(;$)
{   my $self  = shift;
    my $out   = shift || select;

    my $escaped = $self->escapedBody;
    $out->print($self->fromLine);

    my $size  = sum 0, map {length($_)} @$escaped;

    my $head  = $self->head;
    $head->set('Content-Length' => $size); 
    $head->set('Lines' => scalar @$escaped);
    $head->print($out);

    $out->print($_) for @$escaped;
    $out->print("\n");
    $self;
}

sub clone()
{   my $self  = shift;
    my $clone = $self->SUPER::clone;
    $clone->{MBMM_from_line} = $self->{MBMM_from_line};
    $clone;
}

#-------------------------------------------

=section The message

=method fromLine [$line]
Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to generate
one.

If $line is provided, then the starting line is set to this value.
=cut

sub fromLine(;$)
{   my $self = shift;

    $self->{MBMM_from_line} = shift if @_;
    $self->{MBMM_from_line} ||= $self->head->createFromLine;
}

=method escapedBody
Mbox folders contain multiple messages in one file, using a separator
line to keep them apart.  Typically, these lines start with "From ".
Lines within the message could interfere with this separator, and should
therefore be translated.

This method will return the escaped text of the body as reference.
=cut

sub escapedBody()
{   my @lines = shift->body->lines;
    s/^(\>*From )/>$1/ for @lines;
    \@lines;
}

#------------------------------------------

=section Internals

=method readFromParser $parser
Read one message from a M<Mail::Box::File> based folder, including the
leading message separator.
=cut

sub readFromParser($)
{   my ($self, $parser) = @_;
    my ($start, $fromline)  = $parser->readSeparator;
    return unless $fromline;

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;

    $self->SUPER::readFromParser($parser) or return;
    $self;
}

sub loadHead() { shift->head }

=method loadBody
=error Unable to read delayed body.
=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my ($begin, $end) = $body->fileLocation;

    my $parser   = $self->folder->parser;
    $parser->filePosition($begin);

    my $newbody  = $self->readBody($parser, $self->head);
    unless($newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody->contentInfoFrom($self->head));

    $newbody;
}

=method fileLocation
Returns the location of the whole message including the from-line.  In
LIST context, both begin and end are returned.  In SCALAR context, only
the begin is passed back.
=cut

sub fileLocation()
{   my $self = shift;

    wantarray
     ? ($self->{MBMM_begin}, ($self->body->fileLocation)[1])
     : $self->{MBMM_begin};
}

=method moveLocation $distance
The message is relocated in the file, being moved over $distance bytes.
Setting a new location will update the according information in the header
and body.
=cut

sub moveLocation($)
{   my ($self, $dist) = @_;
    $self->{MBMM_begin} -= $dist;

    $self->head->moveLocation($dist);
    $self->body->moveLocation($dist);
    $self;
}

#-------------------------------------------

1;
