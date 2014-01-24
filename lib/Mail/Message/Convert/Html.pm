use strict;
use warnings;

package Mail::Message::Convert::Html;
use base 'Mail::Message::Convert';

use Carp;

=chapter NAME

Mail::Message::Convert::Html - Format messages in HTML

=chapter SYNOPSIS

 use Mail::Message::Convert::Html;
 my $Html = Mail::Message::Convert::Html->new;

 print $html->fieldToHtml($head);
 print $html->headToHtmlHead($head);
 print $html->headToHtmlTable($head);
 print $html->textToHtml($text);

=chapter DESCRIPTION

The package contains various translators which handle HTML or XHTML
without the help of external modules.  There are more HTML related modules,
which do require extra packages to be installed.

=chapter METHODS

=c_method new %options

=option  head_mailto BOOLEAN
=default head_mailto <true>

Whether to replace e-mail addresses in some header lines with links.

=option  produce 'HTML'|'XHTML'
=default produce C<HTML>

Produce HTML or XHTML output.  The output is slightly different, even
html browsers will usually accept the XHTML data.

=cut

sub init($)
{   my ($self, $args)  = @_;

    $self->SUPER::init($args);

    my $produce = $args->{produce} || 'HTML';

    $self->{MMCH_tail}
     = $produce eq 'HTML'  ?   '>'
     : $produce eq 'XHTML' ? ' />'
     : carp "Produce XHTML or HTML, not $produce.";

    $self;
}

#------------------------------------------

=section Converting

=method textToHtml $lines

Translate one or more $lines from text into HTML.  Each line is taken one
after the other, and only simple things are translated.  C<textToHtml>
is able to convert large plain texts in a descent fashion.  In scalar
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

=method fieldToHtml $field, [$subject]

Reformat one header line field to HTML.  The $field's name
is printed in bold, followed by the formatted field content,
which is produced by M<fieldContentsToHtml()>.

=cut

sub fieldToHtml($;$)
{   my ($self, $field, $subject) = @_;
    '<strong>'. $self->textToHtml($field->wellformedName)
    .': </strong>' . $self->fieldContentsToHtml($field,$subject);
}

#------------------------------------------

=method headToHtmlTable $head, [$table_params]

Produce a display of the M<selectedFields()> of the header in a
table shape.  The optional $table_params are added as parameters to the
produced TABLE tag.  In list context, the separate lines are returned.
In scalar context, everything is returned as one.

=examples

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
    {   my $name_html = $self->textToHtml($f->wellformedName);
        my $cont_html = $self->fieldContentsToHtml($f, $subject);
        push @lines, qq(<tr><th valign="top" align="left">$name_html:</th>\n)
                   , qq(    <td valign="top">$cont_html</td></tr>\n);
    }

    push @lines, "</table>\n";
    wantarray ? @lines : join('',@lines);
}

#------------------------------------------

=method headToHtmlHead $head, $meta

Translate the selected header lines (fields) to an html page header.  Each
selected field will get its own meta line with the same name as the line.
Furthermore, the C<Subject> field will become the C<title>,
and C<From> is used for the C<Author>.

Besides, you can specify your own meta fields, which will overrule header
fields.  Empty fields will not be included.  When a C<title> is specified,
this will become the html title, otherwise the C<Subject> field is
taken.  In list context, the lines are separately, where in scalar context
the whole text is returned as one.

If you need to add lines to the head (for instance, http-equiv lines), then
splice them before the last element in the returned list.

=example

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

    foreach my $f ($self->selectedFields($head))
    {   next if exists $meta{$f->name};
        push @lines, '<meta name="' . $self->textToHtml($f->wellformedName)
                   . '" content="'  . $self->textToHtml($f->content)
                   . "\"$self->{MMCH_tail}\n";
    }

    push @lines, "</head>\n";
    wantarray ? @lines : join('',@lines);
}
    
#------------------------------------------

=method fieldContentsToHtml $field, [$subject]

Format one field from the header to HTML.  When the header line usually
contains e-mail addresses, the line is scanned and valid addresses
are linked with an C<mailto:> anchor.  The $subject can be specified to
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

1;
