
use strict;
use warnings;

package Mail::Message::Convert;
use base 'Mail::Reporter';

our $VERSION = 2.010;

=head1 NAME

Mail::Message::Convert - conversions between message types

=head1 CLASS HIERARCHY

 Mail::Message::Convert
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Message::Convert::SomeThing;

 my $convert = Mail::Message::Convert::SomeThing->new;
 my Mail::Message $msg   = Mail::Message->new;
 my SomeThing     $other = $convert->export($msg);

 my SomeThing     $other = SomeThing->new;
 my Mail::Message $msg   = $convert->from($other);

 use Mail::Box::Manager;
 my $mgr     = Mail::Box::Manager->new;
 my $folder  = $mgr->open(folder => 'Outbox');
 $folder->addMessage($other);

=head1 DESCRIPTION

This class is the base for various message converters, which can be
used to translate to and from C<Mail::Message> objects.

You do not have to convert into a C<Mail::Message> explicitly, when you
want to add a foreign message to C<Mail::Box> folder.

The following converters are currently available:

=over 4

=item * C<Mail::Message::Convert::MailInternet>

Converts the simple C<Mail::Internet> messages into C<Mail::Message>
objects.

=item * C<Mail::Message::Convert::MimeEntity>

Converts the more complicated C<MIME::Entity> messages into
C<Mail::Message> objects.

=back

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR).

The general methods for C<Mail::Message::Convert> objects:

   MR errors                            MR new OPTIONS
      export MESSAGE, OPTIONS           MR report [LEVEL]
      from OBJECT, OPTIONS              MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item export MESSAGE, OPTIONS

Returns a new message object based on the information from
a C<Mail::Message> object.  The MESSAGE specified is an
instance of a C<Mail::Message>.

Examples:

 my $convert = Mail::Message::Convert::SomeThing->new;
 my Mail::Message $msg   = Mail::Message->new;
 my SomeThing     $other = $convert->export($msg);

=cut

sub export(@) {shift->notImplemented}

#------------------------------------------

=item from OBJECT, OPTIONS

Returns a new C<Mail::Message> object based on the information from
an message-type which is strange to the C<Mail::Box> set of modules.

Examples:

 my $convert = Mail::Message::Convert::SomeThing->new;
 my SomeThing     $other = SomeThing->new;
 my Mail::Message $msg   = $convert->from($other);

=cut

sub from($@) {shift->notImplemented}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.010.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
