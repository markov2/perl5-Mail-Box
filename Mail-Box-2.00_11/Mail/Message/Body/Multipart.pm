use strict;
use warnings;

package Mail::Message::Body::Multipart;
use base 'Mail::Message::Body';

use Mail::Message::Body::Lines;
use Mail::Message::Part;

our $VERSION = '2.00_11';

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
  MMB data FILE | LIST-OF-LINES |...       parts [MESSAGES]
      epilogue                             preamble [BODY]
   MR errors                           MMB print [FILE]
  MMB file                                 removePart PART|INDEX
  MMB isDelayed                        MMB reply OPTIONS
  MMB isMultipart                       MR report [LEVEL]
  MMB lines                             MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]           MMB size
  MMB message [MESSAGE]                MMB string
  MMB modified [BOOL]                  MMB stripSignature OPTIONS
      new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR DESTROY                           MR logPriority LEVEL
  MMB clone                             MR logSettings
   MR inGlobalDestruction               MR notImplemented
  MMB load                             MMB read PARSER, HEAD, BODYTYPE...

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMB = L<Mail::Message::Body>

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION    DESCRIBED IN                   DEFAULT
 boundary  Mail::Message::Body::Multipart undef
 data      Mail::Message::Body            undef
 epilogue  Mail::Message::Body::Multipart undef
 log       Mail::Reporter                 'WARNINGS'
 message   Mail::Message::Body            undef
 modified  Mail::Message::Body            0
 preamble  Mail::Message::Body::Multipart undef
 parts     Mail::Message::Body::Multipart undef
 trace     Mail::Reporter                 'WARNINGS'

=over 4

=item * parts => ARRAY

Specifies an initial list of parts in this body.

=back

=cut

#------------------------------------------

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMBM_boundary} = $args->{boundary};
    $self->{MMBM_preamble} = $args->{preamble};
    $self->{MMBM_parts}    = $args->{parts} || [];
    $self->{MMBM_epilogue} = $args->{epilogue};
    $self;
}

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

    wantarray ? @lines : \@lines;
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
    return $self->{MMBM_preamble} unless @_;

    $self->{MMB_modified}++ if $self->{MMBM_preamble};
    $self->{MMBM_preamble} = shift;
}

#------------------------------------------

=item epilogue

Returns the epilogue (the text after the last message part --attachment),
optionally after setting it to a new value.  The epilogue is stored in
a BODY object.

=cut

sub epilogue(;$)
{   my $self = shift;
    return $self->{MMBM_epilogue} unless @_;

    $self->{MMB_modified}++ if $self->{MMBM_epilogue};
    $self->{MMBM_epilogue} = shift;
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

    return @{$self->{MMBM_parts}} unless @_;

    $self->{MMB_modified}++ if @{$self->{MMBM_parts}};
    $self->{MMBM_parts} = [ @_ ];
    @_;
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

    $self->{MMB_modified}++;
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
    $self->{MMB_modified}++;
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
    return $self->{MMBM_boundery} if $self->{MMBM_boundery};

    $self->{MMB_modified}++;
    $self->{MMBM_boundery} ||= shift || "boundary-" . $boundary++;
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

sub read($$)
{   my ($self, $parser, $head, $bodytype) = @_;

    my $boundary = 'NO BOUNDARY SPECIFIED';
    if(my $content_type = $head->get('content-type'))
    {   my $comment = $content_type->comment;
        if($comment && $comment =~ m!boundary\=['"](.*?)['"]!)
        {    $boundary = $1;
             $self->{MMBM_boundary} = $boundary;
        }
    }
 
    $parser->pushSeparator("--$boundary");
    my @msgopts  =
     ( $self->logSettings
     , head_wrap => $head->wrapLength
     );

    # Get preamble.
    my $headtype = ref $head;

    my $preamble = Mail::Message::Body::Lines->new(@msgopts)
       ->read($parser, $head);

    $self->{MMBM_preamble} = $preamble if $preamble->size;

    # Get the parts.

    while(my $sep = $parser->readSeparator)
    {   last if $sep eq "--$boundary--\n";

        my $part = Mail::Message::Part->new
         ( @msgopts
         , parent => $self
         );

        last unless $part->read($parser, $bodytype);
        push @{$self->{MMBM_parts}}, $part;
    }

    # Get epilogue

    $parser->popSeparator;
    my $epilogue = Mail::Message::Body::Lines->new(@msgopts)
      ->read($parser, $head);

    $self->{MMBM_epilogue} = $epilogue if $epilogue->size;

    $self;
}

#------------------------------------------

sub clone()
{   my $self     = shift;
    my $preamble = $self->preamble;
    my $epilogue = $self->epilogue;

    ref($self)->new
     ( $self->logSettings
     , boundary => $self->{MMBM_boundary}
     , preamble => ($preamble ? $preamble->clone : undef)
     , epilogue => ($epilogue ? $epilogue->clone : undef)
     , parts    => [ map {$_->clone} $self->parts ]
     );
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

This code is beta, version 2.00_11.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
