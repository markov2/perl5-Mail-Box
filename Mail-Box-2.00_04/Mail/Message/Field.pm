use strict;
use warnings;

package Mail::Message::Field;

use base 'Mail::Reporter';
#use Mail::Box::Parser;

use Carp;

our $VERSION = '2.00_04';
our %_structured;

use overload qq("") => sub { $_[0]->body }
           , '+0'   => 'toInt'
           , cmp    => sub { $_[0]->body cmp "$_[1]" }
           , '<=>'  => sub { $_[0]->toInt <=> $_[1] };


my $crlf = "\015\012";

=head1 NAME

Mail::Message::Field - one line of a Mail::Message header

=head1 SYNOPSIS

   my $field = Mail::Message::Field->new(From => 'me@example.com');
   print $field->name;
   print $field->body;
   print $field->comment;
   $field->print(\*STDOUT);
   print $field->toString;
   print "$field\n";

=head1 DESCRIPTION

The object stores one header-line, and facilitates access routines to
that line.

=over 4

#------------------------------------------

=item new LINE [,REF-ARRAY-OF-OPTIONS]

=item new NAME, BODY [,COMMENT] [,REF-ARRAY-OF-OPTIONS]

Create a new header-object.  Specify the whole header-LINE at once, and
it will be split-up for you.  I case you already have the parts of the
header-line, you may specify them.

In structured fields (a list of pre-defined fields are considered
to have a well-described format, checked with the C<isStructured> method)
everything behind a semi-color is officially a COMMENT.  The comment is
often (ab)used to supply extra information about the body information.

When the field you specify is structured, and you do not specify a comment
yourself, it will be stripped from the LINE or BODY for you.

To keep the communication overlead low (there are too many of these
field-objects to be created), the OPTIONS may be specified as last
argument to C<new>, but as reference to an array.  The following
options are available:

 log               Mail::Reporter     'WARNINGS'
 trace             Mail::Reporter     'WARNINGS'

Examples:

   my @options = (log => 'NOTICE', trace => 'NONE');
   my $mime = Mail::Message::Field->new(
       'Content-Type: text/plain; charset=US-ASCII', \@options);

   my $mime = Mail::Message::Field->new(
       Content-Type => 'text/plain; charset=US-ASCII');

   my $mime = Mail::Message::Field->new(
       Content-Type => 'text/plain', 'charset=US-ASCII');

But, more often, you would call

   my $head = Mail::Message::Head->new;
   $head->add(Content-Type => 'text/plain; charset=US-ASCII');

which implicitly calls this constructor (when needed).

=cut

sub new($;$$)
{   my $options = @_>1 && ref $_[-1] ? pop : [];
    shift->SUPER::new(@$options, create => [@_]);
}

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my ($name, $body, $comment) = @{$args->{create}};

    #
    # Compose the body.
    #

    if(!defined $body)
    {   # must be one line of a header.
        ($name, $body) = split /\:\s*/, $name, 2;

        $self->log(ERROR => "No colon in headerline: $name")
             unless $body;
    }
    elsif($name =~ m/\:/)
    {   $self->log(ERROR => "A header-name cannot contain a colon in $name.");
        return undef;
    }

    $self->log(WARNING=> "Header-field name contains illegal character: $name.")
        if $name =~ m/[^\041-\176]/;

    $body =~ s/\s*\015?\012$//;

    #
    # Take the comment.
    #

    if(defined $comment && length $comment)
    {   # A comment is defined, so shouldn't be in body.
        confess "A header-body cannot contain a semi-colon in $body."
            if $body =~ m/\;/;
    }
    elsif(__PACKAGE__->isStructured($name))
    {   # try strip comment from field-body.
        $comment = $body =~ s/\s*\;\s*(.*)$// ? $1 : undef;
    }

    #
    # Create the object.
    #

    @$self{ qw/MMF_name MMF_body MMF_comment/ } = ($name, $body, $comment);
    $self;
}

#------------------------------------------

=item name

Returns the name of this field, with all characters lower-cased for
ease of comparison.

=cut

sub name() { lc shift->{MMF_name} }

#------------------------------------------

=item body

Returns the body of the field, unmodified but stripped from comment
and CR LF characters (as far as were present at creation).

=cut

sub body() { shift->{MMF_body} }

#------------------------------------------

=item comment

Returns the comment (part after a semi-colon) in the header-line.

=cut

sub comment() { shift->{MMF_comment} }

#------------------------------------------

=item print FILEHANDLE [,CHARS]

Print the whole header-line to the specified file-handle, adding
a new-line after each line which is printed.  One line may result
in more than one printed line, because of the folding of long lines.

=cut

sub print($;$)
{   my ($self, $fh) = (shift, shift);
    $fh->print(join("\n    ",$self->toString(@_)), "\n");
}

#------------------------------------------

=item toString [CHARS]

Returns the whole header-line, without adding anything to the
end of the string (so without CR nor LF character).

In list-context, long lines of structured fields will be folded into
lines with the specified number of CHARacterS not counting the
line-terminators.  "Long" is usually interpreted as lines longer than
65 to 72 characters (default 72).  When set to 0 (zero), no folding
will take place.

Example:

    my @lines = $field->toString(72);
    print $field->toString;
    print "$field";

=cut

sub toString(;$)
{   my $self  = shift;
    my $line  = "$self->{MMF_name}: $self->{MMF_body}"
              . (defined $self->{MMF_comment} ? '; '.$self->{MMF_comment} : '');

    my $fold  = @_ ? shift : 72;
    $fold && wantarray && $self->isStructured
    ? Mail::Box::Parser->defaultParser->foldHeaderLine($line, $fold)
    : $line;
}

#------------------------------------------

=item toInt

Returns the value which is related to this field as integer.  A check is
performed whether this is right.

=cut

sub toInt()
{   my $self  = shift;
    my $value = $self->{MMF_body};
    return $1 if $value =~ m/^\s*(\d+)\s*$/;

    $self->log(WARNING => "Field content is not a numerical value:\n  "
                           . $self->toString . "\n");

    return undef;
}

#------------------------------------------

=item isStructured

(object method or class method)

Examples:

   my $field = Mail::Message::Field->new(From => 'me');
   if($field->isStructured)

   Mail::Message::Field->isStructured('From');

=cut

BEGIN {
%_structured = map { (lc($_) => 1) }
  qw/To Cc Bcc From Date Reply-To Sender
     Resent-Date Resent-From Resent-Sender Resent-To Return-Path
     List-Help List-Post List-Unsubscribe Mailing-List
     Received References Message-ID In-Reply-To
     Content-Length Content-Type
     Delivered-To
     Lines
     MIME-Version
     Precedence
     Status/;
} 

sub isStructured(;$)
{   my $name  = ref $_[0] ? shift->{MMF_name} : $_[1];
    exists $_structured{lc $name};
}

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is alpha version 2.00_00, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Box::Manager>

=cut

1;
