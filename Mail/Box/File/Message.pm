
use strict;
package Mail::Box::File::Message;
use base 'Mail::Box::Message';

use POSIX 'SEEK_SET';
use Carp;

=head1 NAME

Mail::Box::File::Message - one message in a Mbox folder

=head1 SYNOPSIS

 my $folder  = new Mail::Box::File folder => $ENV{MAIL}, ...;
 my $message = $folder->message(0);

=head1 DESCRIPTION

Maintain one message in an file-based folder.

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

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

#------------------------------------------

=head2 Constructing a Message

=cut

#------------------------------------------

sub coerce($)
{   my ($self, $message) = @_;
    return $message if $message->isa(__PACKAGE__);

    $self->SUPER::coerce($message)->labelsToStatus;
}

#-------------------------------------------

=head2 The Message

=cut

#-------------------------------------------

=method print [FILEHANDLE]

Write one message to a file handle.  Unmodified messages are taken
from the folder-file where they were stored.  Modified messages
are written to memory.  Specify a FILEHANDLE to write to
(defaults to the selected handle).

=cut

sub print(;$)
{   my $self  = shift;
    my $out   = shift || select;

    $out->print($self->fromLine);
    $self->SUPER::print($out);
    $out->print("\n");
    $self;
}

#-------------------------------------------

sub clone()
{   my $self  = shift;
    my $clone = $self->SUPER::clone;
    $clone->{MBMM_from_line} = $self->{MBMM_from_line};
    $clone;
}

#-------------------------------------------

=head2 The Header

=cut

#-------------------------------------------

sub head(;$$)
{   my $self  = shift;
    return $self->SUPER::head unless @_;

    my ($head, $labels) = @_;
    $self->SUPER::head($head, $labels);
    $self->statusToLabels if $head && !$head->isDelayed;
    $head;
}

#-------------------------------------------

=head2 Labels

=cut

#-------------------------------------------

sub label(@)
{   my $self   = shift;
    my $return = $self->SUPER::label(@_);
    $self->labelsToStatus if @_ > 1;
    $return;
}

#-------------------------------------------

=head2 Reading and Writing [internals]

=cut

#-------------------------------------------

=method fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to generate
one.

If LINE is provided, then the starting line is set to this value.

=cut

sub fromLine(;$)
{   my $self = shift;

    $self->{MBMM_from_line} = shift if @_;
    $self->{MBMM_from_line} ||= $self->head->createFromLine;
}

#-------------------------------------------

=method read PARSER

Read one message from a Mbox folder, including the message separator.

=cut

sub readFromParser($)
{   my ($self, $parser) = @_;
    my ($start, $fromline)  = $parser->readSeparator;
    return unless $fromline;

    $self->{MBMM_from_line} = $fromline;
    $self->{MBMM_begin}     = $start;

    $self->SUPER::readFromParser($parser) or return;

    $self->{MBMM_parser}    = $parser
        if $self->isDelayed;

    $self;
}

#-------------------------------------------

sub loadHead() { shift->head }

#-------------------------------------------

=method loadBody

=cut

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    my $parser   = delete $self->{MBMM_parser};
    my ($begin, $end) = $body->fileLocation;
    $parser->filePosition($begin);

    my $newbody  = $self->readBody($parser, $self->head);
    unless($newbody)
    {   $self->log(ERROR => 'Unable to read delayed body.');
        return;
    }

    $self->log(PROGRESS => 'Loaded delayed body.');
    $self->storeBody($newbody);

    $newbody;
}

#------------------------------------------

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

#------------------------------------------

=method moveLocation DISTANCE

The message is relocated in the file, being moved over DISTANCE bytes.
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