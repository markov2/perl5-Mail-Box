
use strict;

=head1 NAME

Mail::Box::Mbox::Message - a message in a Mbox folder

=head1 SYNOPSIS

   my $folder  = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
   my $message = $folder->message(0);

=head1 DESCRIPTION

This manual-page describes the classes C<Mail::Box::Mbox::Runtime>,
C<Mail::Box::Mbox::Message>, and C<Mail::Box::Mbox::NotParsed>.
These objects are used to store messages which are not totally read,
fully read, or to be written to a L<Mail::Box::Mbox> type of folder.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message changes from object-class (try to do this in any
other language than Perl!).

All information which is required during the full life-span of the message
is stored in a C<Mail::Box::Mbox::Runtime>, which is extended by
the C<Mail::Box::Mbox::NotParsed> and the C<Mail::Box::Mbox::Message>.  The
last object (C<Mail::Box::Mbox::NotReadHead>) maintains some header-lines
of the message.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=cut

###
### Mail::Box::Mbox::Runtime
###

package Mail::Box::Mbox::Runtime;
use POSIX ':unistd_h';

#-------------------------------------------

=head1 CLASS Mail::Box::Mbox::Runtime

This object contains methods which are part of as well delay-loaded
(not-parsed) as loaded messages, but not general for all folders.

=head2 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in file-based folders use the following extra options for creation:

=over 4

=item * from LINE

The line which precedes each message in the file.  Some people detest
this line, but this is just how things were invented...

=back

=cut

my $unreg_msgid = time;

sub init($)
{   my ($self, $args) = @_;
    $self->{MBM_from_line} = $args->{from};
    $self->{MBM_begin}     = $args->{begin};

    unless(exists $args->{messageID})
    {   my $msgid = $self->head->get('message-id');
        $args->{messageID} = $& if $msgid && $msgid =~ m/\<.*?\>/;
    }
    $self->{MBM_messageID} = $args->{messageID} || 'mbox-'.$unreg_msgid++;

    delete @$args{ qw/from begin/ };

    $self;
}

#-------------------------------------------

=item fromLine [LINE]

Many people detest file-style folders because they store messages all in
one file, where a line starting with C<From > leads the header.  If we
receive a message from a file-based folder, we store that line.  If we write
to such a file, but there is no such line stored, then we try to produce
one.

When you pass a LINE, that this is stored.

=cut

sub fromLine(;$)
{   my $self = shift;

    return $self->{MBM_from_line} = shift if @_;

    return $self->{MBM_from_line} if $self->{MBM_from_line};

    # Create a fake.
    my $from   = $self->head->get('from') || '';
    my $sender = $from =~ m/\<.*?\>/ ? $1 : 'unknown';
    my $date   = $self->head->get('date') || '';
    $self->{MBM_from_line} = "From $sender $date\n";
}

#-------------------------------------------

=item print FILEHANDLE

Write one message to a file-handle.  Unmodified messages are taken
from the folder-file where they were stored in.  Modified messages
are written as in memory.  Specify a FILEHANDLE to write to
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
        print $out $self->fromLine;
        $self->MIME::Entity::print($out);
        print $out "\n";
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
        print $out $msg;
    }

    $folder->fileClose unless $was_open;
    1;
}

#-------------------------------------------

=item migrate FILEHANDLE

Move the message from the current folder, to a new folder-file.  The old
location should be not used after this.

=cut

sub migrate($)
{   my ($self, $out) = @_;
    my $newbegin = tell $out;
    $self->print($out);
    $self->{MBM_begin} = $newbegin;
    $self;
}

###
### Mail::Box::Mbox::Message
###

package Mail::Box::Mbox::Message;
use vars qw/@ISA/;
@ISA = qw(Mail::Box::Mbox::Runtime Mail::Box::Message);

#-------------------------------------------

=back

=head1 CLASS Mail::Box::Mbox::Message

This object extends a C<Mail::Box::Message> with extra tools and facts
on what is special to messages in file-based folders, with respect to
messages in other types of folders.

=head2 METHODS

=over 4

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Message::init($args);
    $self->Mail::Box::Mbox::Runtime::init($args);
    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE into a C<Mail::Box::Mbox::Message>.  When
any message is offered to be stored in a mbox FOLDER, it first should have
all fields which are specific for Mbox-folders.

The coerced message is returned on success, else C<undef>.

Example:

   my $inbox = Mail::Box::Mbox->new(...);
   my $mh    = Mail::Box::MH::Message->new(...);
   Mail::Box::Mbox::Message->coerce($inbox, $mh);
   # Now, the $mh is ready to be included in $inbox.

However, you can better use

   $inbox->coerce($mh);

which will call the right coerce() for sure.

=cut

sub coerce($$)
{   my ($class, $folder, $message) = (shift, shift, shift);
    return $message if $message->isa($class);

    Mail::Box::Message->coerce($folder, $message, @_) or return;

    # When I know more what I can save from other types of messages, later,
    # that information will be extracted here, and transfered into arguments
    # for Runtime->init.

    (bless $message, $class)->Mail::Box::Mbox::Runtime::init;
}

###
### Mail::Box::Mbox::NotParsed
###

package Mail::Box::Mbox::NotParsed;
use vars qw/@ISA/;
@ISA = qw/Mail::Box::Mbox::Runtime
          Mail::Box::Message::NotParsed/;

use IO::InnerFile;

#-------------------------------------------

=back

=head1 CLASS Mail::Box::Mbox::NotParsed

Not parsed messages stay in the file until the message is used.  Because
this folder structure uses many messages in the same file, the byte-locations
are remembered.

=head2 METHODS

=over 4

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::Mbox::Runtime::init(@_);
}

#-------------------------------------------

=item load

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

=cut

sub load($)
{   my ($self, $class) = @_;

    my $folder   = $self->folder;
    my $was_open = $folder->fileIsOpen;
    my $file     = $folder->fileOpen || return 0;
    my $if       = IO::InnerFile->new($file, $self->{MBM_begin}, $self->size)
                || return 0;

    $folder->fileClose unless $was_open;
    my $message = $folder->parser->parse($if);

    # A pitty that we have to copy data now...
    @$self{ keys %$message } = values %$message;

    my $args    = { message  => $message };

    $folder->{MB_delayed_loads}--;

    (bless $self, $class)->delayedInit($args);
}

=back

=head1 IMPLEMENTATION

The user of a folder gets his hand on a message-object, and is not bothered
with the actual data which is stored in the object at that moment.  As
implementor of a mail-package, you might be.

A message is simple to use, but has a quite complex class structure.
A message is not a real message from the start, but only when you access the
body of it.  Before that, a hollow placeholder is used.  Below is depicted
how the internal structure of a message-object changes based on actions on
the object and parameters.

The inheritance relation is like this:

     read()
     =====#
          V              load()
     ::Mbox::NotParsed ========> ::Mbox::Message
           |       \               /    |
           ^        \             /     ^
           |        ::Mbox::Runtime     |
           |                            |
     ::Message::NotParsed           ::Message
                 \                  /   |
                  ::Message::Runtime    ^
                           |            |
                           ^        MIME::Entity
                           |            |
                       ::Thread         ^
                                        |
                                    Mail::Internet

The C<Mail::Box::Mbox::Message> stage, means that the whole message
is in memory.  It then is a full decendent of a C<MIME::Entity>.
But at the same time, it consumes a considerable amount of memory,
and the program has spent quite some processor time on.  All the
intermediate stati are created to avoid full loading, so to be cheap
in memory and time.  Folder access will be much faster under normal
circumstances.

For trained eyes only the status-transition diagram:

   read()     !lazy
   -------> +----------------------------------> Mail::Box::
            |                                  Mbox::Message
            |                                         ^
            |                                         |
            |                    NotParsed    load    |
            |        ALL ,-----> NotReadHead ------>-'|
            | lazy      /                             |
            `--------->+                              |
                        \        NotParsed    load    |
                    REAL `-----> MIME::Head ------->-'


         ,-------------------------+---.
        |                      ALL |   | regexps && taken
        v                          |   |
   NotParsed    head()    get()   /   /
   NotReadHead --------> ------->+---'
             \          \         \
              \ other()  \ other() \regexps && !taken
               \          \         \
                \          \         \    load    Mail::Box::
                 `----->----+---------+---------> MBox::Message

         ,---------------.
        |                |
        v                |
   NotParsed     head()  |
   MIME::Head -------->--'
            \                           Mail::Box::
             `------------------------> MBox::Message


Terms: C<lazy> refers to the evaluation of the C<lazy_extract()> option. The
C<load> and C<load_head> are triggers to the C<AUTOLOAD> mothods.  All
terms like C<head()> refer to method-calls.  Finally, C<ALL>, C<REAL>,
and C<regexps> (default) refer to values of the C<take_headers> option
of C<new()>.

Hm... not that easy...  but relatively simple compared to MH-folder messages.

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.004

=cut

1;
