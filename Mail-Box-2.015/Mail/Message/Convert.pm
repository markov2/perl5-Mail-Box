
use strict;
use warnings;

package Mail::Message::Convert;
use base 'Mail::Reporter';

our $VERSION = 2.015;

=head1 NAME

Mail::Message::Convert - conversions between message types

=head1 CLASS HIERARCHY

 Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

Available methods are very converter-specific.

=head1 DESCRIPTION

This class is the base for various message (and message parts) converters.
Some conversions are looselessly create new object, some are
destroying or adding information.  In most cases, converters are
created by L<Mail::Box> when they are needed.

The following converters are currently available:

=over 4

=item * C<Mail::Message::Convert::Html>

Plays trics with HTML/XMHTML without help of external modules.

=item * C<Mail::Message::Convert::HtmlFormatText>

Converts HTML body objects to plain text objects using the
L<HTML::FormatText> module.

=item * C<Mail::Message::Convert::HtmlFormatPS>

Converts HTML body objects to Postscript objects using the
L<HTML::FormatPS> module.

=item * C<Mail::Message::Convert::MailInternet>

Converts the simple C<Mail::Internet> messages into C<Mail::Message>
objects.

=item * C<Mail::Message::Convert::MimeEntity>

Converts the more complicated C<MIME::Entity> messages into
C<Mail::Message> objects.

=item * C<Mail::Message::Convert::TextAutoformat>

Converts a text message into text using L<Text::Autoformat>.

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR).

The general methods for C<Mail::Message::Convert> objects:

   MR errors                            MR report [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR reportAll [LEVEL]
      new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

 OPTIONS    DESCRIBED IN           DEFAULT
 log        Mail::Reporter         'WARNINGS'
 trace      Mail::Reporter         'WARNINGS'
 fields     Mail::Message::Convert <see description>

=over 4

=item * fields =E<gt> NAMES|ARRAY-OF-NAMES|REGEXS

Select the fields of a header which are to be handled.  Other fields will not
be used.  By default, the C<To>, C<From>, C<Cc>, C<Bcc>, C<Date>, and C<Subject> will be
shown.  Specify an empty list to get all fields. The value of this argument
is passed to the C<grepNames> of L<Mail::Message::Head>.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MMC_fields}          = $args->{fields}    ||
       qr#^(Resent\-)?(To|From|Cc|Bcc|Subject|Date)\b#i;

    $self;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item selectedFields HEAD

Returns a list of fields to be included in the format.  The list is
an ordered selection of the fields in the actual header, and filtered
through the information as specified with the C<fields> option for
C<new>.

=cut

sub selectedFields($)
{   my ($self, $head) = @_;
    $head->grepNames($self->{MMC_fields})
}

1;

=cut

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
