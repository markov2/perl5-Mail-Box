
use strict;

package Mail::Box::MH;

=head1 NAME

Mail::Box::MH::Message - a message in a MH-folder

=head1 SYNOPSIS

   my $folder = new Mail::Box::MH ...
   my $message = $folder->message(10);

=head1 DESCRIPTION

This manual-page describes the classes C<Mail::Box::MH::Message>,
C<Mail::Box::MH::Parsed>, and C<Mail::Box::MH::NotParsed>.  These objects are
used to store messages which are not totally read, fully read, or to be written
to a L<Mail::Box::MH> type of folder.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message changes from object-class (try to do this in any
other language than Perl!).

All information which is required during the full life-span of the message
is stored in a C<Mail::Box::MH::Message>, which is extended by
the C<Mail::Box::MH::NotParsed> and the C<Mail::Box::MH::Parsed>.  The 
last object (C<Mail::Box::MH::NotReadHead>) maintains some header-lines of the
message.

The bottom of this page provides more details about
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=cut

###
### Mail::Box::MH::Message
###

package Mail::Box::MH::Message;
use File::Copy;

#-------------------------------------------

=head1 CLASS Mail::Box::MH::Message

This object contains methods which are part of as well delay-loaded
(not-parsed) as loaded messages, but not general for all folders.

=head2 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

Messages in directory-based folders use the following extra options
for creation:

=over 4

=item * filename =E<gt> FILENAME

The file where the message is stored in.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->{MBM_filename}  = $args->{filename};
    $self;
}

my $unreg_msgid = time;

sub head_init()
{   my $self  = shift;
    my $msgid = $self->head->get('message-id');

    if($msgid && $msgid =~ m/<.*?>/) { $self->{MBM_messageID} = $& }
    else { $self->{MBM_messageID} = 'mh-'.$unreg_msgid++ }

    $self;
}

#-------------------------------------------

=item print TO

Write one message to a file-handle.  Unmodified messages are taken
from the folder-file where they were stored in.  Modified messages
are written as in memory.  Specify a file-handle to write TO
(defaults to STDOUT).

=cut

sub print()
{   my $self     = shift;
    my $out      = shift || \*STDOUT;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    # Modified messages are printed as they were in memory.  This
    # may change the order and content of header-lines and (of
    # course) also the body.  If the message's original file
    # unexplainably disappeared, we also print the internally
    # stored message.

    if(!$self->modified && $filename && -r $filename)
    {   copy($filename, $out);
    }
    else
    {   $self->createStatus->createXStatus;
        $self->MIME::Entity::print($out);
    }

    1;
}

#-------------------------------------------

=item printIndex [FILEHANDLE]

Print the information of this message which is required to maintain
an index-file.  By default, this prints to STDOUT.

=cut

sub printIndex(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $head = $self->head || return $self;
    $head->add('X-MailBox-Filename', $self->filename);
    $head->print($out);
    print $out "\n";
    $self;
}

#-------------------------------------------

=item readIndex CLASS [,FILEHANDLE]

Read the headers of one message from the index into a CLASS
structure.  CLASS is (a sub-class of) a MIME::Head.  If no
FILEHANDLE is specified, the data is read from STDIN.

=cut

sub readIndex($;$)
{   my $self  = shift;
    shift->read(shift, shift || \*STDIN);
}

#-------------------------------------------

=item filename [FILENAME]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub filename(;$)
{   my $self = shift;
    @_ ? $self->{MBM_filename} = shift : $self->{MBM_filename};
}

###
### Mail::Box::MH::Parsed
###

package Mail::Box::MH::Parsed;
use vars '@ISA';
@ISA = qw(Mail::Box::MH::Message Mail::Box::Message::Parsed);

#-------------------------------------------

=back

=head1 CLASS Mail::Box::MH::Parsed

This object extends a Mail::Box::Message with extra tools and facts
on what is special to messages in file-based folders, with respect to
messages in other types of folders.

=head2 METHODS

=over 4

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->Mail::Box::Parsed::init($args);
    $self->Mail::Box::MH::Message::init($args);
    $self;
}

#-------------------------------------------

=item coerce FOLDER, MESSAGE [,OPTIONS]

(Class method)
Coerce a MESSAGE into a Mail::Box::MH::Parsed, ready to be stored in
FOLDER.  When any message is offered to be stored in the mailbox, it
first should have all fields which are specific for MH-folders.

The coerced message is returned on success, else C<undef>.

Example:

   my $mh = Mail::Box::MH->new(...);
   my $message = Mail::Box::Mbox::Message->new(...);
   Mail::Box::MH::Parsed->coerce($mh, $message);
   # Now $message is ready to be stored in $mh.

However, you can better use

   $mh->coerce($message);

which will call coerce on the right message type for sure.

=cut

sub coerce($$)
{   my ($class, $folder, $message) = (shift, shift, shift);
    return $message if $message->isa($class);

    Mail::Box::Message::Parsed->coerce($folder, $message, @_) or return;

    # When I know more what I can save from other types of messages, later,
    # that information will be extracted here, and transfered into arguments
    # for Message->init.

    my $msgid = $message->head->get('message-id');
    $message->{MBM_messageID} = $msgid && $msgid =~ m/<.*?>/ ? $&
                              : 'mh-'.$unreg_msgid++;

    (bless $message, $class)->Mail::Box::MH::Message::init;
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->Mail::Box::Parsed::diskDelete;
    unlink $self->filename;
    $self;
}


###
### Mail::Box::MH::NotParsed
###

package Mail::Box::MH::NotParsed;
use vars '@ISA';
@ISA = qw/Mail::Box::MH::Message
          Mail::Box::Message::NotParsed/;

use IO::InnerFile;

#-------------------------------------------

=back

=head1 CLASS Mail::Box::MH::NotParsed

Not parsed messages stay in the file until the message is used.  Because
this folder structure uses many messages in the same file, the byte-locations
are remembered.

=head2 METHODS

=over 4

=cut

sub init(@)
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::init(@_)
         ->Mail::Box::MH::Message::init(@_);
}

#-------------------------------------------

=item load CLASS [, ARRAY-OF-LINES]

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

If an array of lines is provided, that is parsed as message.  Otherwise,
the file of the message is opened and parsed.

=cut

sub load($;$)
{   my ($self, $class) = (shift, shift);

    my $folder = $self->folder;
    my $new;

    if(@_)
    {   $new = $folder->parser->parse_data(shift);
    }
    else
    {   my $filename = $self->filename;

        unless(open FILE, $filename)
        {   warn "Cannot find folder $folder message $filename anymore.\n";
            return $self;
        }
        $new  =  $folder->parser->parse(\*FILE);
        close FILE;
    }

    my $args = { message => $new };
    $folder->{MB_delayed_loads}--;
    (bless $self, $class)->delayedInit($args);
    $folder->toBeThreaded($self);
    $self;
}

#-------------------------------------------

=item head

Get the head of the message.  This may return immediately, because the
head is already read.  However, when we do not have a header yet, we
read the message.  At this moment, the C<lazy_extract> option of C<new>
comes into action: will we read the whole message now, or only the header?

=cut

sub head()
{   my $self = shift;
    return $self->{MBM_head} if exists $self->{MBM_head};
    $self->folder->readMessage($self->seqnr) or return;
    $self->head;
}

#-------------------------------------------

=item headIsRead

Checks if the head of the message is read.  This is true for fully
parsed messages and messages where the header was accessed once.

=cut

sub headIsRead() { exists shift->{MBM_head} }

#-------------------------------------------

=item messageID

Retreive the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

# This is the only method on a non-parsed object, which implicitly depends
# on a loaded header.  By checking the head, we know for sure that the
# header is loaded.

sub messageID(@)
{   my $self = shift;
    $self->head unless $self->{MBM_head};
    $self->Mail::Box::Message::messageID(@_);
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->Mail::Box::Message::NotParsed::diskDelete;
    unlink $self->filename;
    $self;
}

=back

=head1 IMPLEMENTATION

The user of a folder gets his hand on a message-object, and is not bothered
with the actual data which is stored in the object at that moment.  As
implementor of a mail-package, you might be.

A message is simple to use, but has a quite complex class structure.
A message is not a real message from the start, but only if you access the
body from it.  Till then, you only have a hollow placeholder.  Below is
depicted how the internal status of a message-object changes based on
actions on the object and parameters.

The inheritance relation is like this:

     read()
     =====#
          V              load()
       ::MH::NotParsed ========> ::MH::Parsed
           |       \               /    |
           ^        \             /     ^
           |          ::MH::Message     |
           |                            |
         ::Message                ::Message
        ::NotParsed                ::Parsed
                \                  /    |
                 `--- ::Message --'     ^
                           |            |
                           ^        MIME::Entity
                           |            |
                       ::Thread         ^
                                        |
                                    Mail::Internet

The C<Mail::Box::MH::Parsed> stage, means that the whole message
is in memory.  It then is a full decendent of a C<MIME::Entity>.
But at the same time, it consumes a considerable amount of memory,
and spent quite some processor time.  All the intermediate stati
are created to avoid full loading, so to be cheap in memory and
time.  Random folder access will be much faster by this strategy,
under normal circumstances.

For trained eyes only the transition diagram:

   read()     !lazy && !DELAY
   -------> +----------------------------------> Mail::Box::
            |                                    MH::Parsed
            | lazy && !DELAY && !index                ^
            +--------------.                          |
            |           \   \    NotParsed    load    |
            |            \   `-> NotReadHead ------>-'|
            |        REAL \                           |
            |              \                          |
            | index         v    NotParsed    load    |
            +------------------> MIME::Head ------->-'|
            |                       ^                 |
            |                       |                 |
            |                       |load_head        |
            |                       |                 |
            | DELAY && !index    NotParsed    load    |
            +------------------> <no head> -------->--'


         ,-------------------------+---.
        |                      ALL |   | regexps && taken
        v                          |   |
   NotParsed    head()    get()   /   /
   NotReadHead --------> ------->+---'
             \          \         \
              \ other()  \ other() \regexps && !taken
               \          \         \
                \          \         \    load    Mail::Box::
                 `----->----+---------+---------> MH::Parsed

         ,---------------.
        |                |
        v                |
   NotParsed     head()  |
   MIME::Head -------->--'
            \                           Mail::Box::
             `------------------------> MH::Parsed


                            load_head   NotParsed
                           ,----------> MIME::Head
                          /
   NotParsed    head()   / lazy
   <no head>  --------->+
                         \ !lazy
                          \
                           `-----------> Mail::Box::
                             load        MH::Parsed

Terms: C<lazy> refers to the evaluation of the C<lazy_extract()> option. The
C<load> and C<load_head> are triggers to the C<AUTOLOAD> mothods.  All
terms like C<head()> refer to method-calls.  The C<index> is true if there
is an index-file kept, and the message-header found in there seems still
valid (see the C<keep_index> option of C<new()>).

Finally, C<ALL>, C<REAL>, C<DELAY> (default), and C<regexps> refer to
values of the C<take_headers> option of C<new()>.  Notice that
C<take_headers> on C<DELAY> is more important than C<lazy_extract>.

Hm... not that easy...  Happily, the implementation takes fewer lines than
the documentation.

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.300

=cut

1;
