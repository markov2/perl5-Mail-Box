
use strict;
use warnings;

package Mail::Message::Convert;
use base 'Mail::Reporter';

=head1 NAME

Mail::Message::Convert - conversions between message types

=head1 SYNOPSIS

Available methods are very converter-specific.

=head1 DESCRIPTION

This class is the base for various message (and message parts) converters.
When the conversion does not change the contents of the body, most of
the converters will return the source object.  In any case, an
Mail::Message::Body is returned with the conversion applied but as
much of the other meta data stored in the source body unchanged.

In most cases, converters are created by Mail::Message when they are
needed; have a look at the C<encode> and C<decoded> methods on message
objects.

The following converters are currently available:

=over 4

=item * Mail::Message::Convert::Html

Plays tricks with HTML/XMHTML without help of external modules.

=item * Mail::Message::Convert::HtmlFormatText

Converts HTML body objects to plain text objects using the
L<HTML::FormatText> module.

=item * Mail::Message::Convert::HtmlFormatPS

Converts HTML body objects to Postscript objects using the
L<HTML::FormatPS> module.

=item * Mail::Message::Convert::MailInternet

Converts the simple Mail::Internet messages into Mail::Message
objects.

=item * Mail::Message::Convert::MimeEntity

Converts the more complicated MIME::Entity messages into
C<Mail::Message> objects.

=item * Mail::Message::Convert::TextAutoformat

Converts a text message into text using Text::Autoformat.

=back

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new OPTIONS

=option  fields NAMES|ARRAY-OF-NAMES|REGEXS
=default fields <see description>

Select the fields of a header which are to be handled.  Other fields will not
be used.  The value of this option is passed to Mail::Message::Head::grepNames()
whenever converters feel a need for header line selection.
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

=head2 Converting

=cut

#------------------------------------------

=method selectedFields HEAD

Returns a list of fields to be included in the format.  The list is
an ordered selection of the fields in the actual header, and filtered
through the information as specified with the C<fields> option for
new().

=cut

sub selectedFields($)
{   my ($self, $head) = @_;
    $head->grepNames($self->{MMC_fields})
}

#------------------------------------------

1;
