use strict;
use warnings;

package Mail::Message::Convert::Html;
use base 'Mail::Message::Convert';

our $VERSION = 2.015;
use Carp;

=head1 NAME

Mail::Message::Convert::Html - Format messages from or to HTML

=head1 CLASS HIERARCHY

 Mail::Message::Convert::Html
 is a Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::Html;
 my $Html = Mail::Message::Convert::Html->new;

 print $html->fieldToHtml($head);
 print $html->headToHtmlHead($head);
 print $html->headToHtmlTable($head);
 print $html->textToHtml($text);

=head1 DESCRIPTION

The package contains various translators which handle HTML or XHTML
without the help of external modules.  There are more HTML related modules,
which do require extra packages to be installed.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Message::Convert> (MMC).

The general methods for C<Mail::Message::Convert::Html> objects:

   MR errors                               new OPTIONS
      fieldToHtml FIELD, [SUBJECT]      MR report [LEVEL]
      headToHtmlHead HEAD, META         MR reportAll [LEVEL]
      headToHtmlTable HEAD, [TABL...       textToHtml LINES
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
      fieldContentsToHtml FIELD, ...    MR notImplemented
   MR inGlobalDestruction              MMC selectedFields HEAD

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTION      DESCRIBED IN                   DEFAULT
 fields      Mail::Message::Convert         <some>
 head_mailto Mail::Message::Convert::Html   1
 log         Mail::Reporter                 'WARNINGS'
 produce     Mail::Message::Convert::Html   'HTML'
 trace       Mail::Reporter                 'WARNINGS'

=over 4

=item * head_mailto =E<gt> BOOLEAN

Whether to replace e-mail addresses in some header lines with links.

=item * produce =E<gt> 'HTML'|'XHTML'

Produce HTML or XHTML output.  The output is slightly different, even
html browsers will usually accept the xhtml data.

=back

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    my $produce = $args->{produce} || 'HTML';
    if($produce eq 'HTML')
    {   $self->{MMCH_tail} = '>';
    }
    elsif($produce eq 'XHTML')
    {   $self->{MMCH_tail} = ' />';
    }
    else
    {   croak "Produce XHTML or HTML, not $produce.";
    }

    $self;
}

#------------------------------------------

=item textToHtml LINES

Translate one or more LINES from text into HTML.  Each line is taken one
after the other, and only simple things are translated.  The C<plainToHtml>
method is able to convert large plain texts in a descent fashion.  In scalar
context, the resulting lines are returned as one.

=cut

sub textToHtml(@)
{   my $self  = shift;

    my @lines = @_;    # copy is required
    foreach (@lines)
    {   s/\&/&amp;/gs; s/\</&lt;/gs;
        s/\>/&gt;/gs;  s/\"/&quot;/gs;
    }
    wantarray ? @lines : join('', @lines);
}

#------------------------------------------

=item fieldToHtml FIELD, [SUBJECT]

Reformat one header line field to HTML.  The FIELD's name
is printed in bold, followed by the formatted field content,
which is produced by the C<fieldContentsToHtml> method.

=cut

sub fieldToHtml($;$)
{   my ($self, $field, $subject) = @_;
    '<strong>'. $self->textToHtml($field->wellformedName)
    .': </strong>' . $self->fieldContentsToHtml($field,$subject);
}

#------------------------------------------

=item headToHtmlTable HEAD, [TABLE-PARAMS]

Produce a display of the selected fields of the header (see the
C<selectedFields> method) in a table shape.  The optional
TABLE-PARAMS are added as parameters to the produced TABLE tag.
In list context, the separate lines are returned.  In scalar
context, everything is returned as one.

Example:

 print $html->headToHtmlTable($head, 'width="50%"');

=cut

sub headToHtmlTable($;$)
{   my ($self, $head) = (shift, shift);
    my $tp      = @_ ? ' '.shift : '';

    my $subject;
    if($self->{MMHC_mailto_subject})
    {   my $s = $head->get('subject');

        use Mail::Message::Construct;
        $subject = Mail::Message::Construct->replySubject($s)
            if defined $subject;
    }

    my @lines = "<table $tp>\n";
    foreach my $f ($self->selectedFields($head))
    {   push @lines, '<tr><th valign="top" align="left">'
                     . $self->textToHtml($_->wellformedName).":</th>\n"
                   , '    <td valign="top">'
                     . $self->fieldContentsToHtml($_, $subject)
                     . "</td></tr>\n"
            foreach $head->get($f);
    }

    push @lines, "</table>\n";
    wantarray ? @lines : join('',@lines);
}

#------------------------------------------

=item headToHtmlHead HEAD, META

Translate the selected header lines (fields) to an html page header.  Each
selected field will get its own meta line with the same name as the line.
Futhermore:

=over 4

=item * the C<Subject> field will become the C<title>,

=item * C<From> is used for the C<Author>

=back

Besides, you can specify your own meta fields, which will overrule header
fields.  Empty fields will not be included.  When a C<title> is specified,
this will become the html title, otherwise the C<Subject> field is
taken.  In list context, the lines are separately, where in scalar context
the whole text is returned as one.

If you need to add lines to the head (for instance, http-equiv lines), then
splice them before the last element in the returned list.

Example:

 my @head = $html->headToHtmlHead
     ( $head
     , description => 'This is a message'
     , generator   => 'Mail::Box'
     );
 splice @head, -1, 0, '<meta http-equiv=...>';
 print @head;

=cut

sub headToHtmlHead($@)
{   my ($self, $head) = (shift,shift);
    my %meta;
    while(@_) {my $k = shift; $meta{lc $k} = shift }

    my $title = delete $meta{title} || $head->get('subject') || '<no subject>';

    my @lines =
     ( "<head>\n"
     , "<title>".$self->textToHtml($title) . "</title>\n"
     );

    my $author = delete $meta{author};
    unless(defined $author)
    {   my $from = $head->get('from');
        my @addr = defined $from ? $from->addresses : ();
        $author  = @addr ? $addr[0]->format : undef;
    }

    push @lines, '<meta name="Author" content="'
               . $self->textToHtml($author) . "\"$self->{MMCH_tail}\n"
        if defined $author;

    foreach my $f (map {lc} keys %meta)
    {   next if $meta{$f} eq '';     # empty is skipped.
        push @lines, '<meta name="'. ucfirst lc $self->textToHtml($f)
                   . '" content="'. $self->textToHtml($meta{$f})
                   ."\"$self->{MMCH_tail}\n";
    }

    foreach my $f (sort map {lc} $self->selectedFields($head))
    {   next if exists $meta{$f};

        push @lines, '<meta name="' . $self->textToHtml($_->wellformedName)
                   . '" content="'  . $self->textToHtml($_->content)
                   . "\"$self->{MMCH_tail}\n"
            foreach $head->get($f);
    }

    push @lines, "</head>\n";
    wantarray ? @lines : join('',@lines);
}
    
#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item fieldContentsToHtml FIELD, [SUBJECT]

Format one field from the header to HTML.  When the header line usually
usually contains e-mail addresses, the line is scanned and valid addresses
are linked with an C<mailto:> anchor.  The SUBJECT can be specified to
be included in that link.

=cut

my $atom          = qr/[^()<>@,;:\\".\[\]\s[:cntrl:]]+/;
my $email_address = qr/(($atom(?:\.$atom)*)\@($atom(?:\.$atom)+))/o;

sub fieldContentsToHtml($;$)
{   my ($self, $field) = (shift,shift);
    my $subject = defined $_[0] ? '?subject='.$self->textToHtml(shift) : '';

    my ($body, $comment) = ($self->textToHtml($field->body), $field->comment);

    $body =~ s#$email_address#<a href="mailto:$1$subject">$1</a>#gx
        if $field->name =~ m/^(resent-)?(to|from|cc|bcc|reply\-to)$/;

    $body . ($comment ? '; '.$self->textToHtml($comment) : '');
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.015.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
