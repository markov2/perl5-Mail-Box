
use strict;
package Mail::Box::Mbox::Message;

our $VERSION = 2.00_03;

use POSIX 'SEEK_SET';
use IO::InnerFile;

=head1 NAME

Mail::Box::Mbox::Message - one message in a Mbox folder

=head1 SYNOPSIS

   my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
   my $message = $folder->message(0);

=head1 DESCRIPTION

Maintain one message in an Mbox folder.  See the C<Mail::Message>
documentation for exceptions and extensions to messages which are
Mbox-specific on this page.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in file-based folders use the following options for creation:

 OPTION            DESCRIBED IN              DEFAULT
 body              Mail::Message             undef
 deleted           Mail::Box::Message        0
 folder            Mail::Box::Message        <required>
 from              Mail::Box::Mbox::Message  <created from header>
 head              Mail::Message             undef
 labels            Mail::Box::Message        []
 log               Mail::Reporter            'WARNINGS'
 messageID         Mail::Box::Message        undef
 modified          Mail::Box::Message        0
 size              Mail::Box::Message        undef
 trace             Mail::Reporter           'WARNINGS'

=over 4

=item * from LINE

The line which begins each message in the file. Some people detest
this line, but this is just how things were invented...

=back

=cut

my $unreg_msgid = time;

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_from_line} = $args->{from};
    $self->{MBM_begin}     = $args->{begin};

    unless(exists $args->{messageID})
    {   my $msgid = $self->head->get('message-id');
        $args->{messageID} = $& if $msgid && $msgid =~ m/\<.*?\>/;
    }
    $self->{MBM_messageID} = $args->{messageID} || '<mbox-'.$unreg_msgid++.'>';

    delete @$args{ qw/from begin/ };

    $self;
}

#-------------------------------------------

=item fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to generate
one.

If LINE is provided, then the starting line is set to this value.

=cut

sub fromLine(;$)
{   my $self = shift;

    return $self->{MBM_from_line} = shift if @_;

    return $self->{MBM_from_line} if $self->{MBM_from_line};

    # Create a fake.
    my $from   = $self->head->get('from') || '';
    my $stamp  = $self->timestamp || time;
    my $sender = $from =~ m/\<.*?\>/ ? $& : 'unknown';
    $self->{MBM_from_line} = "From $sender ".(gmtime $stamp)."\n";
}

#-------------------------------------------

=item print [FILEHANDLE]

Write one message to a file handle.  Unmodified messages are taken
from the folder-file where they were stored.  Modified messages
are written to memory.  Specify a FILEHANDLE to write to
(defaults to STDOUT).

=cut

sub print()
{   my $self     = shift;
    my $out      = shift || \*STDOUT;

    my $folder   = $self->folder;
    my $was_open = $folder->fileIsOpen;
    my $file     = $folder->fileOpen;

    if($self->modified)
    {   # Modified messages are printed as they were in memory.  This
        # may change the order and content of header-lines and (of
        # course) also the body.

        $self->createStatus->createXStatus;
        $self->MIME::Entity::print($out);
        ref $out eq 'GLOB' ? print $out "\n" : $out->print("\n");
    }
    else
    {   # Unmodified messages are copied directly from their folder
        # file: fast and exact.
        my $size = $self->size;

        seek $file, $self->{MBM_begin}, SEEK_SET;

        my $msg;
        unless(defined read($file, $msg, $size))
        {   warn "Could not read $size bytes for message from $folder.\n";
            $folder->fileClose unless $was_open;
            return 0;
        }

        # required for perl <5.6.0, otherwise just $out->print($msg)
        ref $out eq 'GLOB' ? print $out $msg : $out->print($msg);
    }

    $folder->fileClose unless $was_open;
    1;
}

#-------------------------------------------

=item migrate FILEHANDLE

Move the message from the current folder to a new folder-file.  The old
location should be not used after this operation is performed.

=cut

sub migrate($)
{   my ($self, $out) = @_;
    $out->print($self->fromLine);
    my $newbegin = tell $out;
    $self->print($out);
    $self->{MBM_begin} = $newbegin;
    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE object into a C<Mail::Box::Mbox::Parsed>
object.  When any message is offered to be stored in an Mbox FOLDER, this
method should be called first to make sure that the object has all the
fields which are specific to Mbox folders.

MESSAGE is a reference to a (probably non-Mbox) message, which is then
changed into a C<Mail::Box::Mbox::Message> object. The coerced message is
also returned on success, otherwise C<undef> is returned and MESSAGE is
left unchanged.

Example:

   my $inbox = Mail::Box::Mbox->new(...);
   my $mh    = Mail::Box::MH::Message->new(...);
   Mail::Box::Mbox::Message->coerce($inbox, $mh);
   # Now, the $mh is ready to be included in $inbox.

However, you can just use

   $inbox->coerce($mh);

which will always call coerce() on the right message type.

=cut

sub coerce($$)
{   my ($class, $folder, $message) = (shift, shift, shift);
    return $message if $message->isa(__PACKAGE__);

    $class->SUPER::coerce($folder, $message, @_);
}

#-------------------------------------------

=item loadHead

=item loadBody

This method is called by the autoloader when the data of the message
is needed.  For Mbox folders, you will always get both header and
body, even if only the header is needed.

=cut

sub load($)
{   my ($self, $class) = @_;
    return $self unless $self->isDelayed;

    my $folder   = $self->folder;
    my $was_open = $folder->fileIsOpen;
    my $file     = $folder->fileOpen || return 0;
    my $if       = IO::InnerFile->new($file, $self->{MBM_begin}, $self->size)
                || return 0;

    my $parser  = $folder->parser;
    my $message = eval {$parser->parse($if)};
    my $error   = $@ || $parser->last_error;
    warn "Error $error" if $error;

    $folder->fileClose unless $was_open;

    my $args    = { message  => $message };
    $self->delayedInit($args);
}

sub loadHead($)
{   my $self = shift;
    $self->headIsDelayed ? $self->load->head : $self->head;
}

sub loadBody($) { shift->load->body }

=back

=head1 IMPLEMENTATION

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_03

=cut

1;
