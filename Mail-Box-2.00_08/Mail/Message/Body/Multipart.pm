use strict;
use warnings;

package Mail::Message::Body::Multipart;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

our $VERSION = '2.00_08';

use Carp;

=head1 NAME

 Mail::Message::Body::Multipart - Body of a Mail::Message with attachments

=head1 CLASS HIERARCHY

 Mail::Message::Body::Multipart
 is a Mail::Message::Body
 is a Mail::Reporter

=head1 SYNOPSIS

 See Mail::Message::Body, plus

 if($body->isMultipart) {
    my @attachments = $body->parts;
    my $attachment3 = $body->part(2);
    my $before      = $body->preamble;
    my $after       = $body->epiloque;
    my $removed     = $body->removePart(1);
 }

=head1 DESCRIPTION

READ C<Mail::Message::Body> FIRST. This manual-page only describes the
extentions to the default body functionality.

The body (content) of a message can be stored in various ways.  In this
manual-page you find the description of extra functionality you have
when a message contains attachments (parts).

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Multipart> objects:

      attach MESSAGES                  MMB nrLines
      boundary [STRING]                    part INDEX
  MMB clone                                parts [MESSAGES]
  MMB data FILE | LIST-OF-LINES |...       preamble [BODY]
      epilogue                         MMB print [FILE]
   MR errors                               removePart PART|INDEX
  MMB file                             MMB reply OPTIONS
  MMB isDelayed                         MR report [LEVEL]
  MMB isMultipart                       MR reportAll [LEVEL]
  MMB lines                            MMB size
   MR log [LEVEL [,STRINGS]]           MMB string
  MMB message [MESSAGE]                MMB stripSignature OPTIONS
  MMB new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

  MMB load                              MR notImplemented
   MR logPriority LEVEL                MMB read PARSER, HEAD, BODYTYPE...
   MR logSettings                      MMB start

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>

=head1 METHODS

=over 4

=cut

#------------------------------------------

sub init()
{   my $self = shift;
    $self->{MMBM_parts} = [];
    $self;
}

#------------------------------------------

sub clone() {}

#------------------------------------------

sub string() { join '', shift->lines }

#------------------------------------------

sub lines()
{   my $self     = shift;

    my $boundary = $self->boundary;
    my @lines;

    my $preamble = $self->preamble;
    push @lines, $preamble->lines if $preamble;

    foreach ($self->parts)
    {   push @lines, "--$boundary\n", $_->body->lines;
    }

    push @lines, "\n--$boundary--\n";

    my $epilogue = $self->epilogue;
    push @lines, $epilogue->lines if $epilogue;

    @lines;
}

#------------------------------------------

sub file() {}

#------------------------------------------

sub nrLines()
{   my $self   = shift;
    my $nr     = 1;

    if(my $preamble = $self->preamble) { $nr += $preamble->nrLines }
    $nr       += 2 + $_->nrLines foreach $self->parts;
    if(my $epilogue = $self->epilogue) { $nr += $epilogue->nrLines }

    $nr;
}

#------------------------------------------

sub size()
{   my $self   = shift;
    my $bbytes = length($self->boundary) +3;

    my $bytes  = 0;
    if(my $preamble = $self->preamble) { $bytes += $preamble->size }
    $bytes    += $bbytes + 2;  # last boundary
    $bytes    += $bbytes + 1 + $_->size foreach $self->parts;
    if(my $epilogue = $self->epilogue) { $bytes += $epilogue->size }

    $bytes;
}

#------------------------------------------

sub print(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $boundary = $self->boundary;
    if(my $preamble = $self->preamble)
    {   $preamble->print($out);
    }

    my @parts    = $self->parts;
    while(@parts)
    {   $out->print("--$boundary\n");
        shift(@parts)->print($out);
        $out->print("\n");
    }

    $out->print("--$boundary--\n");

    if(my $epilogue = $self->epilogue)
    {   $epilogue->print($out);
    }

    $self;
}

#------------------------------------------

sub isMultipart() {1}

#------------------------------------------

=item preamble [BODY]

Returns the preamble (the text before the first message part --attachment),
optionally after setting it to a new value.  The preamble is stored in
a BODY object.

=cut

sub preamble(;$)
{   my $self = shift;
    @_ ? $self->{MMBM_preamble} = shift : $self->{MMBM_preamble};
}

#------------------------------------------

=item epilogue

Returns the epilogue (the text after the last message part --attachment),
optionally after setting it to a new value.  The epilogue is stored in
a BODY object.

=cut

sub epilogue(;$)
{   my $self = shift;
    @_ ? $self->{MMBM_epilogue} = shift : $self->{MMBM_epilogue};
}

#------------------------------------------

=item parts [MESSAGES]

In LIST context, the current list of parts (attachments) is returned,
optionally after setting it to the specified new list first.  If any
MESSAGES are specified, all current parts are replaced.

In SCALAR context the length of the list is returned, so the number
of parts for this multiparted body.  This is normal behavior of Perl.

Examples:

 print "Number of attachments: ", scalar $message->body->parts;

 foreach my $part ($message->body->parts) {
     print "Type: ", $part->head->get('content-type')->body;
 }

=cut

sub parts(@)
{   my $self = shift;
    $self->{MMBM_parts} = [ @_ ]  if @_;
    @{$self->{MMBM_parts}};
}

#-------------------------------------------

=item part INDEX

Returns only the part with the specified INDEX.  You may use a negative
value here, which counts from the back in the list.

Example:

 $message->body->part(2)->print;

=cut

sub part($) { shift->{MMBM_parts}[shift] }

#-------------------------------------------

=item removePart PART|INDEX

Removes the part on the specified INDEX in the list.  When a PART is
specified, the INDEX is looked-up first.  The INDEX may be negative,
which counts from the back of the list.  The removed part is returned.

=cut

sub removePart($)
{   my ($self, $part) = @_;
    my $index = $part;

    if(ref $part)
    {   my $index = 0;
        foreach ($self->parts)
        {   last if $_ eq $part;
            $index++;
        }
    }

    splice @{$self->{MMBM_parts}}, $index, 1;
}

#-------------------------------------------

=item attach MESSAGES

Add messages to the list of message-parts.  The message-parts will be
coerced into a C<Mail::Message::Part>, so you may attach C<Mail::Internet>
or C<MIME::Entity> objects if you want --see C<Mail::Message::coerce()>.
The coerced messages are returned.

Examples:

 my $part = Mail::Message->new;
 $multiparted->body->attach($part);

 my $entity  = MIME::Entity->new;
 my $coerced = $multipart->body->attach($entity);
 # $coerced is a Mail::Message representation of $entity's data.

=cut

sub attach(@)
{   my $self = shift;
    my @coerced = map {Mail::Message::Part->coerce($_)} @_;
    push @{$self->{MMBM_parts}}, @coerced;
    @coerced;
}

#-------------------------------------------

=item boundary [STRING]

Returns the boundary which is used to separate the parts in this
body.  If none was read from file, then one will be assigned.  With
STRING you explicitly set the boundary to be used.

=cut

my $boundary = time;

sub boundary(;$)
{   my $self = shift;
    $self->{MMBM_boundery} = shift if @_;

    $self->{MMBM_boundery} ||= "boundary-" . $boundary++;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub data(@)
{   croak <<CROAK;
You cannot add data to a multipart at initiation.  Attach parts per
piece, and so construct the information.  Or read the data from a
file with a parser.
CROAK
}

#-------------------------------------------

sub read($$$;$$)
{   my ($self, $parser, $head, $getbodytype) = splice @_, 0, 4;
confess "$head, $getbodytype, @_" unless ref $getbodytype;

    my $boundary = 'NO BOUNDARY SPECIFIED';
    if(my $content_type = $head->get('content-type'))
    {   if($content_type->comment =~ m!boundary\=['"](.*?)['"]!)
        {    $boundary = $1;
             $self->{MMBM_boundary} = $boundary;
        }
    }
 
    $parser->pushSeparator("--$boundary");
    my @log      = $self->logSettings;

    # Get preamble.
    my $headtype = ref $head;

    my $preamble = Mail::Message::Body::Lines->new(@log)
                   ->read($parser, $head, $getbodytype);
    $self->preamble($preamble) if $preamble->size;

    # Get the parts.

    while(my $sep = $parser->readSeparator)
    {   last if $sep eq "--$boundary--\n";

        my $part = Mail::Message::Part->new(@log, parent => $self);
        last unless $part->read($parser, $headtype, $getbodytype);
        $self->attach($part);
    }

    # Get epilogue

    $parser->popSeparator;
    my $epilogue = Mail::Message::Body::Lines->new(@log)
                   ->read($parser, $head, $getbodytype);
    $self->epilogue($epilogue) if $epilogue->size;

    $self;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_08.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
