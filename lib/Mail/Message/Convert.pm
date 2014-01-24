
use strict;
use warnings;

package Mail::Message::Convert;
use base 'Mail::Reporter';

=chapter NAME

Mail::Message::Convert - conversions between message types

=chapter SYNOPSIS

Available methods are very converter-specific.

=chapter DESCRIPTION

This class is the base for various message (and message parts) converters.

=section Converters between message objects
Internally, the M<Mail::Message::coerce()> is called when foreign objects
are used where message objects are expected.  That method will automatically
create the converting objects, and re-use them.

=over 4
=item * M<Mail::Message::Convert::MailInternet>
Converts the simple M<Mail::Internet> messages into M<Mail::Message>
objects.

=item * M<Mail::Message::Convert::MimeEntity>
Converts the more complicated M<MIME::Entity> messages into
M<Mail::Message> objects.

=item * M<Mail::Message::Convert::EmailSimple>
Converts M<Email::Simple> messages into M<Mail::Message> objects.

=back

=section Other converters

=over 4

=item * M<Mail::Message::Convert::Html>
Plays tricks with HTML/XMHTML without help of external modules.

=item * M<Mail::Message::Convert::HtmlFormatText>
Converts HTML body objects to plain text objects using the
HTML::FormatText module.

=item * M<Mail::Message::Convert::HtmlFormatPS>
Converts HTML body objects to Postscript objects using the
M<HTML::FormatPS> module.

=item * M<Mail::Message::Convert::TextAutoformat>
Converts a text message into text using M<Text::Autoformat>.

=back

=chapter METHODS

=c_method new %options

=option  fields NAMES|ARRAY-OF-NAMES|REGEXS
=default fields <see description>

Select the fields of a header which are to be handled.  Other
fields will not be used.  The value of this option is passed to
M<Mail::Message::Head::Complete::grepNames()> whenever converters feel
a need for header line selection.
By default, the C<To>, C<From>, C<Cc>, C<Bcc>, C<Date>, C<Subject>, and their
C<Resent-> counterparts will be selected.  Specify an empty list to get all
fields.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMC_fields}          = $args->{fields}    ||
       qr#^(Resent\-)?(To|From|Cc|Bcc|Subject|Date)\b#i;

    $self;
}

#------------------------------------------

=section Converting

=method selectedFields $head

Returns a list of fields to be included in the format.  The list is
an ordered selection of the fields in the actual header, and filtered
through the information as specified with M<new(fields)>.

=cut

sub selectedFields($)
{   my ($self, $head) = @_;
    $head->grepNames($self->{MMC_fields});
}

#------------------------------------------

=section Error handling

=cut

1;
