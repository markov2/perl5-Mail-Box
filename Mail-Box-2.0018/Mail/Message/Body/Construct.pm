use strict;
use warnings;

# Mail::Message::Body::Construct adds functionality to Mail::Message::Body

package Mail::Message::Body;

use Carp;
use IO::Scalar;

use Mail::Message::Body::String;
use Mail::Message::Body::Lines;

=head1 NAME

Mail::Message::Body::Construct - adds functionality to Mail::Message::Body

=head1 CLASS HIERARCHY

 Mail::Message::Body::String
 is a Mail::Message::Body
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

This package adds complex functionality to the C<Mail::Message::Body>
class.  This functions less often used, so many programs will not
compile this package.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Body::Construct> objects:

      attach MESSAGES, OPTIONS             foreachLine CODE
      concatenate COMPONENTS               stripSignature OPTIONS

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item foreachLine CODE

Create a new body by performing an action on each of its lines.  If none
of the lines change, the current body will be returned, otherwise a new
body is created of the same type as the current.

The CODE refers to a subroutine which is called, where C<$_> contains
body's original line.  DO NOT CHANGE C<$_>!!!  The result of the routine
is taken as new line.  When the routine returns C<undef>, the line will be
skipped.

Examples:

 my $content  = $msg->decoded;
 my $reply    = $content->foreachLine( sub { '> '.$_ } );
 my $rev      = $content->foreachLine( sub {reverse} );

 sub filled() { length $_ > 1 ? $_ : undef }
 my $nonempty = $content->foreachLine( \&filled );

 my $wrong    = $content->foreachLine( sub {s/a/A/} );  # WRONG!!!
 my $right    = $content->foreachLine( sub {(my $x=$_) =~ s/a/A/} );

=cut

sub foreachLine($)
{   my ($self, $code) = @_;
    my $changes = 0;
    my @result;

    foreach ($self->lines)
    {   my $becomes = $code->();
        if(defined $becomes)
        {   push @result, $becomes;
            $changes++ if $becomes ne $_;
        }
        else {$changes++}
     }
      
     return $self unless $changes;

     ref($self)->new
      ( based_on => $self
      , data     => \@result
      );
}

#------------------------------------------

=item concatenate COMPONENTS

Concatenate a list of elements into one new body.  The encoding is defined by
the body where this method is called upon (and which does not need to be
included in the result).

Specify a list of COMPONENTS.  Each component can be

=over 4

=item a message (C<Mail::Message>), the body of the message is used,

=item a body (C<Mail::Message::Body>),

=item C<undef>, which will be skipped,

=item a scalar, which is split on new-lines,

=item an array of scalars, each providing one line.

=back

Example:

 # all arguments are C<Mail::Message::Body>'s.
 my $sum = $body->concatenate($preamble, $body, $epilogue, "--\n" , $sig);

=cut

sub concatenate(@)
{   my $self = shift;

    my @bodies;
    foreach (@_)
    {   next unless defined $_;
        push @bodies
         , !ref $_           ? Mail::Message::Body::String->new(data => $_)
         : ref $_ eq 'ARRAY' ? Mail::Message::Body::Lines->new(data => $_)
         : $_->isa('Mail::Message')       ? $_->body
         : $_->isa('Mail::Message::Body') ? $_
         : carp "Cannot concatenate element ".@bodies;
    }

    my @unified;

    my $changes  = 0;
    foreach my $body (@bodies)
    {   my $unified = $self->unify($body);
        if(defined $unified)
        {   $changes++ unless $unified==$body;
            push @unified, $unified;
        }
        elsif($body->mimeType->mainType eq 'text')
        {   # Text stuff can be unified anyhow, although we do not want to
            # include postscript or such.
            push @unified, $body;
        }
        else { $changes++ }
    }

    return $self if @bodies==1 && $bodies[0]==$self;  # unmodified, and single

    ref($self)->new
      ( based_on => $self
      , data     => [ map {$_->lines} @unified ]
      );
}

#------------------------------------------

=item attach MESSAGES, OPTIONS

Make a multipart containing this body and the specified MESSAGES. The
options are passed to the constructor of the multi-part body.  If you
need more controle, create the multi-part body yourself.  At least
take a look at L<Mail::Message::Body::Multipart>.

The message-parts will be coerced into a C<Mail::Message::Part>, so you
may attach C<Mail::Internet> or C<MIME::Entity> objects if you want --see
C<Mail::Message::coerce()>.  A new body with attached messages is
returned.

Examples:

 my $pgpkey = Mail::Message::Body::File->new(file => '.pgp');
 my $msg    = Mail::Message->buildFromBody(
    $message->decoded->attach($pgpkey));

 my $entity  = MIME::Entity->new;
 my $multi   = $msg->body->attach($entity);
 # The last message of the $multi multiparted body is the coerced $entity.

=cut

sub attach(@)
{   my $self  = shift;

    my @parts;
    push @parts, shift while @_ && ref $_[0];

    return $self unless @parts;
    unshift @parts, $self;

    Mail::Message::Body::Multipart->new(parts => \@parts, @_);
}

#------------------------------------------

=item stripSignature OPTIONS

Strip the signature from the body.  The body must already be decoded
otherwise the wrong lines may get stripped.

The signature is added by the sender to tell about him-
or herself.  It is superfluous in some situations, for instance if you
want to create a reply to the person's message you do not need to include
that signature.

<stripSignature> returns the stripped version body, and in list context
also the signature, encapsulated in its own body object.  If the body had
no signature, the original body object is returned, and C<undef> for
the signature body.  The signature separator is the first line of the
returned signature body.

 OPTIONS     DESCRIBED IN                   DEFAULT
 result_type Mail::Message::Body::Construct <same as current>
 pattern     Mail::Message::Body::Construct <same as current>
 max_lines   Mail::Message::Body::Construct 10

=over 4

=item * result_type =E<gt> CLASS

The type of body to be created for the stripped body (and maybe also to
contain the stripped signature)

=item * pattern =E<gt> REGEX|STRING|CODE

Which pattern defines the line which indicates the separator between
the message and the signature.  In case of a STRING, this is matched
to the beginning of the line, and REGEX is a full regular expression.

In case of CODE, each line (from last to front) is passed to the
specified subroutine as first argument.  The subroutine must return
TRUE when the separator is found.

By default, the scan is for the regular expression C<qr/^--(\s|$)/>.

=item * max_lines =E<gt> INTEGER

The maximum number of lines which can be the length of a signature, which
defaults to 10.  Specify C<undef> to remove the limit.

=back

Examples:

 my $stripped = $message->decoded;
 my $stripped = $body->decoded;
 my ($stripped, $signature) = $message->decoded
    ->stripSignature(max_lines => 5, pattern => '-*-*-');

=cut

# tests in t/51stripsig.t

sub stripSignature($@)
{   my ($self, %args) = @_;

    return $self if $self->mimeType->isBinary;

    my $pattern = !defined $args{pattern} ? qr/^--(\s|$)/
                : !ref $args{pattern}     ? qr/^\Q${args{pattern}}/
                :                           $args{pattern};
 
    my $lines   = $self->lines;   # no copy!
    my $stop    = defined $args{max_lines}? @$lines - $args{max_lines}
                : exists $args{max_lines} ? 0 
                :                           @$lines-10;

    $stop = 0 if $stop < 0;
    my ($sigstart, $found);
 
    if(ref $pattern eq 'CODE')
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $pattern->($lines->[$sigstart]);
            $found = 1;
            last;
        }
    }
    else
    {   for($sigstart = $#$lines; $sigstart >= $stop; $sigstart--)
        {   next unless $lines->[$sigstart] =~ $pattern;
            $found = 1;
            last;
        }
    }
 
    return $self unless $found;
 
    my $bodytype = $args{result_type} || ref $self;

    my $stripped = $bodytype->new
      ( based_on => $self
      , data     => [ @$lines[0..$sigstart-1] ]
      );

    return $stripped unless wantarray;

    my $sig      = $bodytype->new
      ( based_on => $self
      , data     => [ @$lines[$sigstart..$#$lines] ]
      );
      
    ($stripped, $sig);
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_18.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
