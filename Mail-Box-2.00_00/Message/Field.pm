
package Mail::Message::Field;

use strict;
use warnings;
use Carp;

our $VERSION = '2.00_00';

use Mail::Box::Parser;
use overload qq("") => 'toString';
use vars qw/%_structured/;

my $crlf = "\015\012";

=head1 NAME

Mail::Message::Field - UNDER CONSTRUCTION: one line of a Mail::Message header

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

=item new LINE

=item new NAME, BODY [,COMMENT]

Create a new header-object.  The NAME is the field's label in the header
of the message, but it also may be a while header-line.

When the NAME is only the name of a field,  then the second argument is
the BODY, containing the related information from the header.

In structured fields (a list of pre-defined fields-names are considered
to have a well-described format, checked with the C<isStructured> method)
everything behind a semi-color is officially a COMMENT, but it is
often (ab)used to supply extra information about the body information.

BE WARNED: header-lines which where parsed by the Mail::Box modules
coming from a file are not created by this C<new()> method, but inside
C<Mail::Box::Parser>.  Use this constuctor to add fields to an existing
header, or to create fields for a new message.

Examples:

   my $mime = Mail::Message::Field->new(
       'Content-Type: text/plain; charset=US-ASCII');

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
{   my ($class, $name, $body, $comment) = @_;

    #
    # Compose the body.
    #

    if(defined $body)
    {
        confess "A header-name cannot contain a colon in $name."
           if $name =~ m/\:/;
    }
    else
    {   # must be one line of a header.
        ($name, $body) = split /\:\s*/, $name, 2;

        confess "Error: wrong header-line."
             unless $body;
    }

    confess "Header-field name contains illegal character: $name."
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

    bless { MMF_name => $name, MMF_body => $body, MMF_comment => $comment }
       , $class;
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
65 to 72 characters (default 72).

Example:

    my @lines = $field->toString(72);
    print $field->toString;

=cut

sub toString(;$)
{   my $self  = shift;
    my $line  = "$self->{MMF_name}: $self->{MMF_body}"
              . (defined $self->{MMF_comment} ? '; '.$self->{MMF_comment} : '');

    wantarray && $self->isStructured
    ? Mail::Box::Parser::fold_header_line($line, shift || 72)
    : $line;
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

This code is alpha version 1.318, and far from complete.  Please
contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::Box::Manager>

=cut

1;
