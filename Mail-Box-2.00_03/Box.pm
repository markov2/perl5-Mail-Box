
use strict;
use warnings;

package Mail::Box;
use base 'Mail::Reporter';
use Mail::Box::Message;
use Mail::Box::Locker;

our $VERSION = '2.00_03';

use Carp;
use Scalar::Util 'weaken';

use overload '@{}' => 'as_row';
use overload '""'  => 'name';
use overload 'cmp' => sub {$_[0]->name cmp "${_[1]}"};

=head1 NAME

Mail::Box - Manage a message-folder.

=head1 SYNOPSIS

   use Mail::Box::Manager;
   my $mgr    = Mail::Box::Manager->new;
   my $folder = $mgr->open(folder => $ENV{MAIL}, ...);
   print $folder->name;

   # Get the first message.
   print $folder->message(0);

   # Delete the third message
   $folder->message(3)->delete;

   # Get the number of undeleted messages in scalar context.
   my $emails = $folder->messages;

   # Iterate over the messages.
   foreach ($folder->messages) {...}     # undeleted messages
   foreach ($folder->allMessages) {...}  # all messages
   foreach (@$folder) {...}              # undeleted messages

   $folder->addMessage(new Mail::Box::Message(...));

Tied-interface:   (See Mail::Box::Tie)

   tie my(@inbox), 'Mail::Box::Tie::ARRAY', $inbox;
   $inbox[3]->print        # same as $folder->message(3)->print

   tie my(%inbox), 'Mail::Box::Tie::HASH', $inbox;
   $inbox{$msgid}->print   # same as $folder->messageID($msgid)->print


=head1 DESCRIPTION

A C<Mail::Box::Manager> creates C<Mail::Box> objects, so you may want to
begin there.

C<Mail::Box> is the base-class for accessing various types of mail-folder
organizational structures in a uniform way.  The various folder types vary
on how they store their messages. For example, a folder may store many
messages in a single file, or store each message in a separate file in a
directory. Similarly, there may be different techniques for locking the
folders.

The C<Mail::Box> is used to get C<Mail::Box::Message> objects from the
mailbox.  Applications then usually use information or add information to the
message object. For instance, the application can set a flag which indicates
whether a message has been replied to or not. In addition, applications can
extend C<Mail::Box::Message> by deriving from it. See C<Mail::Box::Message>
and its derived classes for more information.

=head1 METHODS

Unless indicated otherwise, all methods are instance methods.

=over 4

=item new ARGS

(Class method) Open a new folder. ARGS is a list of labeled parameters
defining options for the mailboxes. Some options pertain to Mail::Box, and
others are added by sub-classes. The list below describes all the options
provided by Mail::Box and the various sub-classes distributed with it. Those
provided by the Mail::Box class are described in detail here. For a
description of the other options, see the documentation for the respective
sub-class.

 OPTION            DEFINED BY         DEFAULT
 access            Mail::Box          'r'
 body_type         Mail::Box   #      <differs per folder-type>
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          <no default>
 head_wrap         Mail::Box          72
 head_type         Mail::Box   #      'Mail::Message::Head'
 head_partial_type Mail::Box   #      head_type . '::Partial'
 head_delayed_type Mail::Box   #      head_type . '::Delayed'
 lazy_extract      Mail::Box          10kb
 lock_file         Mail::Box::Locker  foldername.'.lock'
 lock_method       Mail::Box::Locker  'DOTLOCK'
 lock_timeout      Mail::Box::Locker  1 hour
 lock_wait         Mail::Box::Locker  10 seconds
 log               Mail::Reporter     'WARNINGS'
 manager           Mail::Box   #      undef
 message_type      Mail::Box   #      'Mail::Box::Message'
 organization      Mail::Box   #      'FILE'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 trace             Mail::Reporter     'WARNINGS'
 take_headers      Mail::Box          <specify everything you need>
 <none>            Mail::Box::Tie

Options marked by C<#> are only useful to extend C<Mail::Box>, for instance
within the implementation of C<Mail::Box::Mbox>.  As normal users of folders,
you will not specify them.

The normal usage options for C<Mail::Box::new()> are:

=over 4

=item * access =E<gt> MODE

Access-rights to the folder. MODE can be read-only (C<"r">), append (C<"a">),
and read-write (C<"rw">).  Folders are opened for read-only (C<"r">) by
default.

These modes have nothing in common with the modes actually used to open the
folder-files within this module.  For instance, if you specify C<"rw">, and
open the folder, only read-permission on the folder-file is required.  Writing
to a folder will always create a new file to replace the old one.

=item * folder =E<gt> FOLDERNAME

Which folder to open (for reading or writing). When used for reading (the
C<access> option set to C<"r"> or C<"a">) the mailbox should already exist
and be readable. The file or directory of the mailbox need not exist if it
is opened for reading and writing (C<"rw">).  Write-permission is checked when
opening an existing mailbox.

=item * folderdir =E<gt> DIRECTORY

Where are folders written by default?  You can specify a folder-name
preceeded by C<=> to explicitly state that the folder is located below
this directory.  For example: if C<folderdir =E<gt> '/tmp'> and
C<folder =E<gt> '=abc'>, then the name of the folder-file is C<'/tmp/abc'>.

=item * head_wrap =E<gt> INTEGER

Fold the structured headers to the specified length (defaults to C<72>).
Folding is disabled when C<0> is specified.

=item * save_on_exit =E<gt> BOOL

Sets the policy for saving the folder when it is closed. (See the
C<close()> method.)  A folder can be closed manually or via a number of
implicit methods (including when the program is terminated). By default
this option is set to TRUE.

=item * remove_when_empty =E<gt> BOOL

Determines whether or not to remove the folder file or directory
automatically when the write would result in a folder without sub-folders
or messages. This option is dependent on the type of folder, and is true by
default.

=back

To control delay-loading of messages, as well the headers as the bodies,
the next three option specify the algorithm.  The C<take_headers> determine
whether we parse the full header or less, C<lazy_extract> determines whether
we want delay-loading, and C<body_type> determines which kind of body we want
when we decide to parse it.

=over 4

=item * lazy_extract =E<gt> INTEGER

=item * lazy_extract =E<gt> CODE

=item * lazy_extract =E<gt> METHOD

=item * lazy_extract =E<gt> 'NEVER'|'ALWAYS'

If you supply a number to this option, bodies of those messages with a
total size less than that number will be extracted from the folder only
when nessesary.  Headers will always be extracted, even from the larger
messages.  This reduces the memory-footprint of the program, with only
little cost.

If you supply a code reference, that subroutine is called every time
that the extraction mechanism wants to determine whether to parse the
body or not. The subroutine is called with the following arguments:

    $code->(FOLDER, HEADER)

where FOLDER is a reference to the folder we are reading.  HEADER refers to an
C<Mail::Message::Header>.  The routine must return a true value (be lazy: delay
extract) or a false value (extract now).  Think about using the
C<guessBodySize()> and C<guessTimestamp()> on the header to determine
your choice.

The third possibility is to specify the NAME of a method.  In that case,
for each message is called:

   FOLDER->NAME(HEADER)

Where each parameter has the same meaning as described above.

The fourth way to use this parameter involves constants: with C<'NEVER'>
you can disable delayed loading. With C<'ALWAYS'> you force unconditional
loading.

Examples:

    $folder->new(lazy_extract => 'NEVER');
    $folder->new(lazy_extract => 10000);
    $folder->new(lazy_extract => sub {$_[3] >= 10000 }); #same

    $folder->new(lazy_extract => 'sent_by_me');
    sub Mail::Box::send_by_me($$$$)
    {   my ($self, $header, $lines, $bytes) = @_;
        $header->get('from') =~ m/\bmy\@example.com\b/i;
    }

=item * take_headers =E<gt> ARRAY-REGEXPS|REGEXP|'ALL'|'NONE'

When a folder is read, but you donot want to store all header-lines for
fast access, then specify a list of headers with this option.  By
default this is set to C<'ALL'> to take all headers.

See C<registerHeaders()> below, for a detailed explanation.  Please try
to avoid calling that method when you can do with using this option.

Examples:

   $folder->new( take_headers  => 'ALL');
   $folder->new( take_headers  => 'Subject');
   $folder->new( take_headers  => [ 'X-Mutt-.*', 'X-Folder-.*' ]);

=item * body_type =E<gt> CLASS|CODE

When messages are read from a folder-file, the headers will be stored in
a C<head_type>-object.  For the body, however, there is a range of
choices about type, which are all described in the C<Mail::Message::Body>
manual page.

Specify a CODE-reference which produces the body-type to be created, or
a CLASS of the body which is used when the body is not a multipart.  In case
of a code, the header-structure is passed as first argument of the routine.
For instance:

   $mgr->open(body_type => \&which_body);

   sub which_body($) {
       my $head = shift;
       my $type = $head->isMultipart            ? 'Multipart'
                : $head->guessBodySize > 100000 ? 'File'
                :                                 'Lines';
       "Mail::Message::Body::$type";
   }

The default depends on the mail-folder type.  Please check the applicatable
manual pages.

=back

Options for extension-writers are:

=over 4

=item * head_type =E<gt> CLASS

=item * head_partial_type =E<gt> CLASS

=item * head_delayed_type =E<gt> CLASS

Specify a different header object-type to keep respectively all, some,
or none of the header-lines which are related to one message.  See
C<Mail::Message::Head> about the differences.

The default for C<head_type> is C<Mail::Message::Head>.  The default
for C<head_partial_type> will add C<::Partial> to the C<head_type>,
where C<head_delayed_type> add C<::Delayed>.

=item * manager =E<gt> MANAGER

A reference to the object which manages this folder -- typically an
C<Mail::Box::Manager> instance.

=item * message_type =E<gt> CLASS

What kind of message-objects are stored in this type of folder.  The
default is Mail::Box::Message (which is a sub-class of Mail::Message).
The class you offer must be an extension of C<Mail::Box::Message>.

=item * organization =E<gt> 'FILE' | 'DIRECTORY'

Tells whether a folder is one file containing many messages (like
Mbox-folders) or one directory per folder, a message per file
(like MH-folders).

=back

=cut

sub new(@)
{   my $class        = shift;

    if($class eq __PACKAGE__)
    {   use Carp;
        my $package = __PACKAGE__;

        croak <<USAGE;
You should not instantiate $package directly, but rather one of the
sub-classes, such as Mail::Box::Mbox.  If you need automatic folder
type detection then use Mail::Box::Manager.
USAGE
    }

    my $self = $class->SUPER::new
      ( @_
      , init_options => [ @_ ]  # for clone
      );

warn "Now reading.";
    $self->read;
warn "Reading done";
    $self;
}

sub init($)
{   my ($self, $args) = @_;
    my $class = ref $self;

    unless(defined $args->{folder})
    {   warn "No folder specified.\n";
        return;
    }

    $self->{MB_init_options} = $args->{init_options};
    $self->{MB_message_opts} = $args->{message_options}   || [];
    $self->{MB_foldername}   = $args->{folder}            || $ENV{MAIL};
    $self->{MB_access}       = $args->{access}            || 'r';
    $self->folderdir($args->{folderdir});

    $self->{MB_remove_empty} = $args->{remove_when_empty} || 1;
    $self->{MB_messages}     = [];
    $self->{MB_modifications}= 0;
    $self->{MB_save_on_exit} = $args->{save_on_exit}      || 1;
    $self->{MB_organization} = $args->{organization}      || 'FILE';

    if(exists $args->{manager})
    {   $self->{MB_manager}      = $args->{manager};
        weaken $self->{MB_manager};
    }

    my $message_type         = $self->{MB_message_type}
        = $args->{message_type}     || $class . '::Message';
    $self->{MB_body_type}
        = $args->{body_type}        || 'Mail::Message::Body';
    my $head_type            = $self->{MB_head_type}
        = $args->{head_type}        || 'Mail::Message::Head';
    $self->{MB_head_partial_type}
        = $args->{head_partial_type}|| $head_type.'::Partial';
    $self->{MB_head_delayed_type}
        = $args->{head_delayed_type}|| $head_type.'::Delayed';

    for($args->{lazy_extract} || 10000)
    {   my $extract = $_;
        $self->{MB_lazy_extract}
          = ref $_ eq 'CODE' ? $_
          : $_ eq 'NEVER'    ? sub {0}
          : $_ eq 'ALWAYS'   ? sub {1}
          : m/\D/            ? sub {no strict 'refs';$self->$extract(@_)}
          :                    sub {$_[3] >= $extract}
    }

    $self->registerHeaders(qw/date from mail-from subject status x-status/
        , qw/message-id in-reply-to references/    # for threads
        );

    #
    # Inventory on which header-lines we will have to take.
    #

    $self->registerHeaders( ref $args->{take_headers}
                          ? @{$args->{take_headers}}
                          : $args->{take_headers}
                          ) if exists $args->{take_headers};

    #
    # Create a locker.
    #

    my $locker = $args->{lock_method};
    if($locker && ref $locker)
    {   confess "No locker object passed."
            unless $locker->isa('Mail::Box::Locker');
        $self->{MB_locker} = $locker;
    }
    else
    {   $self->{MB_locker} = Mail::Box::Locker->new
            ( folder      => $self
            , lock_method => $locker
            , lock_timeout=> $args->{lock_timeout}
            , lock_wait   => $args->{lock_wait}
            , lock_file   => $args->{lockfile} || $args->{lock_file}
            );
    }

    $self;
}

#-------------------------------------------

=item clone [OPTIONS]

Create a new folder, with the same settings as this folder.  One of
the specified options must be new folder to be opened.  Other options
overrule those of the folder where this is a clone from.

Example:

   my $folder2 = $folder->clone(folder => '=jan');

=cut

sub clone(@)
{   my $self  = shift;

    (ref $self)->new
     ( @{$self->{MB_init_options}}
     , @_
     );
}

#-------------------------------------------

=item registerHeaders REGEXP [,REGEXP, ...]

=item registeredHeaders

The C<registerHeaders> method can be used to specify which header
lines should be taken while scanning through a folder.  Its
counterpart C<registeredHeaders> returns the current header fetching
specification.

Use this method to specify additional headers that you use frequently
and would like C<Mail::Box> to parse by default. Repeated header
specifications are not a problem.

If you specify too few field-names then it's likely that you will access a
header that you did not specify, forcing the entire message to be parsed (read
from file into memory). When you specify too many fields, your program will
consume much more memory.

You can select headers using a list of regular expressions, or by using
special patterns. The special pattern C<ALL> is provided by all
mail folders. Particular folder sub-types may support additional special
patterns, such as the C<NONE> pattern supported by MH mailboxes.

An alternative to C<registerHeaders> is to use index files. If the folder type
supports them, you can use index files to read the header lines, thereby
avoiding any delays resulting from having to read the mailbox files or folders
directly. Consult the documentation for the folder type in order to find out
if it supports index files.

=over 4

=item * 'ALL' to indicate that all headers should be taken.

Indicates that all header lines should be retrieved (same as pattern C<.*>)

=item * 'NONE'

Indicates that no headers should be taken until a line from the header is
required. This is useful for folders where each message has to be read from a
separate source. In this case, we would like to delay interaction with the
source as long as possible.

=item * a list of regular expressions

If you use parentheses then also use C<"?:"> to make sure that a match is not
stored in a capture buffer (C<$1>, C<$2>, etc).  For example, you should use
C<X-(?:ab|cd).*> instead of C<X-(ab|cd).*>.  Regular expressions will always
be matched on the whole header field. So C<X-.*> will only match headers
which start with C<X->.

=back

Examples:

   $folder->registerHeaders('ALL');
   $folder->registerHeaders('Subject', 'X-Folder-.*');

=cut

# REAL and DELAY where available in Mail::Box < v2.0

sub registerHeaders(@)
{   my $self = shift;

    if(grep {$_ eq 'ALL' || $_ eq 'REAL' || $_ eq '.*'} @_)
    {   $self->{MB_take_headers} = 'ALL';
    }
    elsif(grep {$_ eq 'NONE' || $_ eq 'DELAY' } @_)
    {   $self->{MB_take_headers} = 'NONE';
    }
    elsif(exists $self->{MB_take_headers} && !ref $self->{MB_take_headers})
    {  # Already an important constant defined: no change to be made.
    }
    else { map {$self->{MB_take_headers}{lc $_}++} @_ }

    $self;
}

sub registeredHeaders()
{   my $patterns = shift->{MB_take_headers};
    ref $patterns ? keys %$patterns : $patterns;
}

#-------------------------------------------

=item read OPTIONS

Read messages from the folder into memory. If there are already messages in
memory, the new ones are added.

NOTE: if you are copying messages from one folder to another, use
C<addMessages> instead of C<read>.

=cut

sub read(@)
{   my $self = shift;
    $self->{MB_open_time}     = time;

    # Read from existing folder.
    return unless $self->readMessages(@_);

    $self->{MB_modifications} = 0;  #after reading, no changes found yet.
    $self;
}

sub readMessages(@) {croak "readMessages not implemented by ".(ref(shift))."\n"}

#-------------------------------------------

=item write [OPTIONS]

Write the data to disk.  The folder is returned if successful. To write to a
different file, you must first create a new folder, then move the messages,
and then write the folder.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

As options you may specify

=over 4

=item * force =E<gt> BOOL

Override write-protection by the C<access> option while opening the folder
(whenever possible, it may still be blocked by the operating system).

=item * keep_deleted =E<gt> BOOL

Do not remove messages which were flagged to be deleted from the folder
from memory, but do remove them from disk.

=item * save_deleted =E<gt> BOOL

Do also write messages which where flagged to be deleted to their folder.  The
flag is conserved (when possible), which means that the next write may
remove them for real.

=back

=cut

sub write(@)
{   my ($self, %args) = @_;

    unless($args{force} || $self->writeable)
    {   warn "Folder $self is opened read-only.\n";
        return;
    }

    unless($args{keep_deleted})
    {   my @keep;

        foreach my $message ($self->allMessages)
        {   if($message->deleted)
            {   $message->diskDelete;
                unless($message->headIsDelayed)
                {   $self->messageID($message->messageID, undef);
                    $self->toBeUnthreaded($message);
                }
            }
            else
            {   push @keep, $message;
            }
        }

        $self->{MB_messages}      = [ @keep ];
        $self->{MB_alive}         = [ @keep ];
    }

    $self->{MB_modifications} = 0;
    $args{messages}
        = $args{save_deleted} ? [ $self->allMessages ] : [ $self->messages ];

    $self->writeMessages(\%args);
}

#-------------------------------------------

=item close OPTIONS

lose the folder, optionally writing it. C<close> takes the same options as
C<write>, as well as a few others:

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before writing and closing the source folder.  Otherwise
you may lose data if the system crashes or if there are software problems.

=over 4

=item * write =E<gt> 'ALWAYS'|'NEVER'|'MODIFIED'

Specifies whether the folder should be written.  As could be expected,
C<'ALWAYS'> means always (even if there are no changes), C<'NEVER'> means that
changes to the folder will be lost, and C<'MODIFIED'> (which is the default)
only saves the folder if there are any changes.

=item * force =E<gt> BOOL

Override the C<access> setting specified when the folder was opened. This
option only has an effect if its value is TRUE. NOTE: Writing to the folder
may not be permitted by the operating system, in which case even C<force> will
not help.

=back

=cut

sub close(@)
{   my ($self, %args) = @_;
    my $force = $args{force} || 0;

    return if exists $self->{MB_is_closed};
    $self->{MB_is_closed} = 1;

    # Inform manager that the folder is closed.
    $self->{MB_manager}->close($self)
        if exists $self->{MB_manager}
           && !$args{close_by_manager};

    delete $self->{MB_manager};

    my $write
      = !exists $args{write} || $args{write} eq 'MODIFIED' ? $self->modified
        : $args{write} eq 'ALWAYS'                         ? 1
        : $args{write} eq 'NEVER'                          ? 0
        :                                                    0;

    if($write && !$force && !$self->writeable)
    {   warn "Changes not written to read-only folder.\n";
        return 1;
    }

    my $rc = $write
           ? $self->write(force => $force)
           : 1;

    $self->{MB_locker}->unlock;
    $rc;
}

#-------------------------------------------

=item delete

Remove the specified folder file or folder directory (depending on
the type of folder) from disk.  Of course, THIS IS DANGEROUS: you "may"
lose data.

WARNING: When moving messages from one folder to another, be sure to write the
destination folder before deleting the source folder.  Otherwise you may lose
data if the system crashes or if there are software problems.

Examples:

   my $folder = Mail::Box::File->new(folder => 'InBox');
   $folder->delete;

=cut

sub delete()
{   my $self = shift;

    # Extra protection: do not remove read-only folders.
    unless($self->writeable)
    {   warn "Folder $self is opened read-only, so not removed.\n";
        return;
    }

    # Sub-directories need to be removed first.
    foreach ($self->listFolders)
    {   my $sub = $self->openSubFolder($_);
        next unless $sub;
        $sub->delete;
        $sub->close;
    }

    # A lock may protect destruction from interference.
    $self->lock;
    $_->delete foreach $self->messages;
    $self->{MB_remove_empty} = 1;

    my $rc = $self->write(keep_deleted => 0);
    $self->unlock;
    $rc;
}

#-------------------------------------------

sub openSubFolder(@)
{   my $self    = shift;
    my @options = (@{$self->{MB_init_options}}, @_);

    $self->{MB_manager}
    ?  $self->{MB_manager}->open(@options)
    :  (ref $self)->new(@options);
}

#-------------------------------------------

=item name

Returns the name of the folder.  What the name represents depends on
the actual type of mailbox used.

Example:

   print $folder->name;

=cut

sub name() { shift->{MB_foldername} }

#-------------------------------------------

=item writeable

Checks whether the current folder is writeable.

Example:

    $folder->addMessage($msg) if $folder->writeable;

=cut

sub writeable() { shift->{MB_access} =~ /w|a/ }
sub readable()  {1}  # compatibility

#-------------------------------------------

=item modified

=item modifications INCR

C<modified> checks if the folder is modified. C<modifications> is
used to tell the folder how many changes are made in messages.  The
INCR value can be negative to undo effects.

=cut

sub modified($)       { shift->{MB_modifications} }
sub modifications(;$) { shift->{MB_modifications} += shift||1 }

#-------------------------------------------

=item lazyExtract HEADER, BODY, SIZE

Calls the subroutine which will determine whether a message's body should be
extracted, or whether it should stay in the folder until used.  This method
calls the routine defined by the C<lazy_extract> option during folder creation.

=cut

sub lazyExtract($$$)
{   my $self = shift;
    $self->{MB_lazy_extract}->($self, @_);
}

#-------------------------------------------

=item message INDEX [,MESSAGE]

Get or set a message with on a certain index.  Messages which are flagged
for deletion are counted.  Negative indexes start at the end of the folder.

See the C<activeMessage> method to index message that are not marked
for deletion.

Examples:

    my $msg = $folder->message(3);
    $folder->message(3)->delete;   # status changes to `deleted'
    $folder->message(3, $msg);
    print $folder->message(-1);    # last message.

=cut

sub message(;$$)
{   my ($self, $index) = (shift, shift);
    @_ ?  $self->{MB_messages}[$index] = shift : $self->{MB_messages}[$index];
}

#-------------------------------------------

=item organization

Return whether a folder is organized as one 'FILE' with many messages or
a 'DIRECTORY' with one message per file.

=cut

sub organization() { shift->{MB_organization} }

#-------------------------------------------

=item messageID MESSAGE-ID [,MESSAGE]

With one argument, returns the message in the folder with the specified
MESSAGE-ID. If a reference to a message object is passed as the optional
second argument, the message is first stored in the folder, replacing any
existing message whose message ID is MESSAGE-ID. (The message ID of MESSAGE
need not match MESSAGE-ID.)

WARNING: when the message headers are delay-parsed, the message might be in
the folder but not yet parsed into memory. In this case, use the C<find()>
method instead of C<messageID> if you really need a thorough search.

=cut

sub messageID($;$)
{   my ($self, $msgid) = (shift, shift);

    return $self->{MB_msgid}{$msgid} unless @_;

    my $message = shift;

    # Undefine message?
    unless($message)
    {   delete $self->{MB_msgid}{$msgid};
        return;
    }

    # Auto-delete doubles.
    if(my $double = $self->{MB_msgid}{$msgid})
    {   $message->delete unless $double->isa('Mail::Box::Message::Dummy');
        return $message;
    }

    $self->{MB_msgid}{$msgid} = $message;
}

#-------------------------------------------

=item find MESSAGE-ID

Like C<messageID()>, this method searches for a message with the
MESSAGE-ID, returning the corresponding message object.  However, C<find()>
will cause unparsed message in the folder to be parsed until the message-id
is found.  The folder will be scanned back to front.

=cut

sub find
{   my ($self, $msgid) = (shift, shift);
    my $msgids = $self->{MB_msgid};
    return $msgids->{$msgid} if exists $msgids->{$msgid};
    $self->scanForMessages(undef, $msgid, 'EVER', 'ALL');
    $msgids->{$msgid};
}

#-------------------------------------------

=item messages

Returns all messages which are I<not> scheduled to be deleted.  In scalar
context, it returns the number of undeleted messages in the folder.
Dereferencing a folder to an array is overloaded to call this method.

Examples:

    foreach ($folder->messages) {...}
    foreach (@$folder)
    my $remaining_size = $folder->messages;
    $folder->[2]   # third not-deleted message

=cut

sub messages()
{   my $self = shift;

    # We often call this method, so we optimize not to check for `deleted'
    # all the time.  If a message is deleted, it is hard to determine which
    # message in the `alive' list should be removed, so in that case, this
    # list gets invalidated.
    $self->{MB_alive} = [ grep {! $_->deleted} $self->allMessages ]
       unless exists $self->{MB_alive};

    @{$self->{MB_alive}};
}

sub as_row()
{   my Mail::Box $self = shift;
    $self->messages unless exists $self->{MB_alive};
    $self->{MB_alive};
}

#-------------------------------------------

=item activeMessage INDEX [,MESSAGE]

Returns the message indicated by INDEX from the list of non-deleted
messages.

=cut

sub activeMessage($;$)
{   my ($self, $index) = (shift, shift);
    @_ ? $self->as_row->[$index] = shift : $self->as_row->[$index];
}

#-------------------------------------------

=item allMessages

Returns a list of I<all> messages in the folder, including
those which are marked to be deleted.

Examples:

    foreach my $msg ($folder->allMessages)
    {   $msg->print;
    }
    my $total_size = $folder->allMessages;

=cut

sub allMessages()   { @{shift->{MB_messages}} }

#-------------------------------------------

=item allMessageIDs

Returns a list of I<all> message-ids in the folder, including
those which are to be deleted.

For some folder-types (like MH), this method may cause all message-files
to be read.  See their respective manual pages.

Examples:

    foreach my $id ($folder->allMessageIDs)
    {   $folder->messageID($id)->print;
    }

=cut

sub allMessageIDs() { keys %{shift->{MB_msgid}} }

#-------------------------------------------

=item addMessage  MESSAGE

=item addMessages MESSAGE [, MESSAGE, ...]

Add a message to the folder.  A message is usually a C<Mail::Box::Message>
object or a sub-class thereof.  The message shall not be in an other folder,
when you use this method.  In case it is, use C<moveMessage()> or
C<copyMessage()>.

Messages with id's which already exist in this folder are not added.

Examples:

   $folder->addMessage($msg);
   $folder->addMessages($msg1, $msg2, ...);

=cut

sub addMessage($)
{   my $self    = shift;
    my $message = shift or return $self;

    confess <<ERROR if $message->can('folder') && $message->folder;
You cannot add a message which is already part of a folder to a new
one.  Please use moveMessage or copyMessage.
ERROR

    # Force the message into the right folder-type.
    $self->coerce($message);

    unless($message->head->isDelayed)
    {   # Do not add the same message twice.
        my $msgid = $message->messageID;
        my $found = $self->messageID($msgid);
        return $self if $found && !$found->isDummy;

        $self->messageID($msgid, $message);
    }
    else
    {   # Messages where even the header is not known let are still
        # added to the folder.  However, they need to publish their
        # message-id themselves at parse-time.
        $message->folder($self);
    }

    push @{$self->{MB_messages}}, $message;

    push @{$self->{MB_alive}}, $message
        unless $message->deleted || !exists $self->{MB_alive};

    $message->seqnr( @{$self->{MB_messages}} -1);
    $self->{MB_modifications}++;
    $self;
}

sub addMessages(@)
{   my Mail::Box $self = shift;
    $self->addMessage($_) foreach @_;
    $self;
}

#-------------------------------------------

=item appendMessages OPTIONS

(Class method) Append one or more messages to an unopened folder.
Usually, this method is called by the Mail::Box::Manager (its method
C<appendMessage()>), in which case the correctness of the
folder type is checked.
 
This method takes a list of labeled parameters, which may contain
any option which can be used when a folder is opened (most importantly
C<folderdir>).  Two aditional parameters shall be specified:

=over 4

=item * folder =E<gt> FOLDERNAME

The name of the folder to which the messages are to be appended.  The folder
implementation will avoid opening the folder when possible, because this is
resource consuming.

=item * message =E<gt> MESSAGE

=item * messages =E<gt> ARRAY-OF-MESSAGES

One reference to a MESSAGE or a reference to an ARRAY of MESSAGEs, which may
be of any type.  The messages will be first coerced into the correct
message type to fit in the folder, and then will be added to it.

=back

=cut

sub appendMessages(@)
{   my ($class, $foldername) = @_;
    use Carp;
    confess "Foldertype $class does not implement appendMessages.\n";
    $class;
}

#-------------------------------------------

=item coerce MESSAGE

Coerce the message to be of the correct type to be placed in the
folder.

=cut

sub coerce($)
{   my ($self, $message) = @_;

    # We do not have to take actions when we have the right type for
    # this folder.

    if(   $message->isa($self->{MB_message_type})
       || $message->isa($self->{MB_notparsed_type}))
    {   $message->folder($self);
        return $message;
    }

    # Be sure that the message is loaded, before it is converted
    # to a new type.
    $message->forceLoad if $message->can('forceLoad');

    # Convert to the right type for this mailbox.
    $self->{MB_message_type}->coerce
       ( $self, $message
       , @{$self->{MB_message_opts}}
       , modified => 1
       );

    $self;
}

#-------------------------------------------

=item messageDeleted MESSAGE|MESSAGE-ID, BOOL

Used to indicate when a message has been deleted or undeleted, in order to
reset internal data structures in the folder. This method is called
automatically when you call the C<delete> method on a MESSAGE. If the BOOL is
true, the message was deleted; otherwise it was undeleted.

=cut

sub messageDeleted($$)
{   my $self = shift;

    # Simply remove the list which contains the list of active messages.
    # When you call $folder->messages after this, the list of active
    # messages is re-generated.
    # Maybe, in the future, this can be optimized, using the parameters,
    # but I expect this is not possible.

    delete $self->{MB_alive};
    $self;
}

#-------------------------------------------

=item folderdir [DIR]

Get or set the directory which is used to store mail-folders by default.

Examples:

   print $folder->folderdir;
   $folder->folderdir("$ENV{HOME}/nsmail");

=cut

sub folderdir(;$)
{   my $self = shift;
    @_ ? ($self->{MB_folderdir} = shift) : $self->{MB_folderdir};
}

#-------------------------------------------

=item current [NUMBER|MESSAGE|MESSAGE-ID]

Some mail-readers keep the I<current> message, which represents the last
used message.  This method returns [after setting] the current message.
You may specify a NUMBER, to specify that that message number is to be
selected as current, or a MESSAGE/MESSAGE-ID (as long as you are sure that the
header is already loaded, otherwise they are not recognized).

Examples:

   $folder->current(0);
   $folder->current($message);

=cut

sub current(;$)
{   my $self = shift;
    return $self->{MB_current} || $self->message(-1)
        unless @_;

    my $next = shift;
    if(my $previous = $self->{MB_current})
    {    $previous->setLabel(current => 0);
    }

    ($self->{MB_current} = $next)->setLabel(current => 1);
}

#-------------------------------------------

=item DESTROY

This method is called by Perl when an folder-object is no longer accessible
by the rest of the program.

=cut

sub DESTROY
{   my $self = shift;
    $self->close unless $self->{MB_is_closed};
}

#-------------------------------------------

=back

=head2 folder management methods

The following class methods are used to test and list folders.  They all
support the C<folderdir> option, where you can specify the default location
for the folder-files.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

(class method) Determine if the specified folder is of the type handled by the
folder class. This method is extended by each folder sub-type.

The FOLDERNAME specifies the name of the folder, as is specified by the
application.  OPTIONS is a list of extra information for the request.  Read
the documentation for each type of folder for folder-specific options, but
each folder class will at least support the C<folderdir> option:

=over 4

=item * folderdir =E<gt> DIRECTORY

The location where the folders of this class are stored by default.  If the
user specifies a name starting with a C<=>, that indicates that the folder is
to be found in this default DIRECTORY.

=back

=cut

sub foundIn($@)
{   my ($class, $folder, @options) = @_;
    die "$class could not autodetect type of $folder.";
}

#-------------------------------------------

=item create FOLDERNAME [, OPTIONS]

(Class method) Create a folder.  If the folder already exists, it will
be left unchanged.  As options, you may specify:

=over 4

=item * folderdir =E<gt> DIRECTORY

When the foldername is preceeded by a C<=>, the C<folderdir> directory
will be searched for the named folder.

=back

=cut

sub create($@)
{   my ($class, $name, @options) = @_;
    die "$class cannot create a folder named $name.\n";
}

#-------------------------------------------

=item listFolders [OPTIONS]

(Class and Instance method) List all folders which belong to a certain class
of folders.  Each sub-class shall extend this method.  As a class method, the
C<folder> option is usually used (defaults to the top folderdir).  This method
will return the sub-folders of the opened folder when called as an instance
method.

At least the following options are supported, but refer to the manpage
of the various folder sub-classes to see more options.

=over 4

=item * folder =E<gt> FOLDERNAME

The folder whose sub-folders should be listed.

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

Specifies whether empty folders (folders which currently do not contain any
messages) should be included. It may not be useful to open empty folders, but 
saving to them is useful.

=item * skip_empty =E<gt> BOOL

Shall empty folders (folders which currently do not contain any messages)
be included?  Empty folders are not useful to open, but may be useful
to save to.

=back

Examples:

   my $folder = $mgr->open('=in/new');
   my @subs = $folder->listFolders;

   my @subs = Mail::Box::Mbox->listFolders(folder => '=in/new');
   my @subs = Mail::Box::Mbox->listFolders; # toplevel folders.

=cut

sub listFolders(@)
{   my ($class, @options) = @_;
    die "$class cannot list folders.";
}

#-------------------------------------------

# Call locking methods.

sub lock()         { shift->{MB_locker}->lock    }
sub unlock()       { shift->{MB_locker}->unlock  }
sub isLocked()     { shift->{MB_locker}->isLocked}
sub hasLock()      { shift->{MB_locker}->hasLock }
sub lockMethod()   { shift->{MB_locker}->name    }
sub lockFilename() { shift->{MB_locker}->filename}

#-------------------------------------------

=head2 METHODS of writing extensions

The next set of methods is for normal use, but only for people who
write entensions (develop new folder-types).

=over 4

=cut

#-------------------------------------------

=item toBeThreaded MESSAGES

=item toBeUnthreaded MESSAGES

The specified message is ready to be included in (or remove from) a thread.
This will be passed on to the mail-manager, which keeps an overview on
which thread-detection objects are floating around.

=cut

sub toBeThreaded(@)
{   my $self = shift;

    my $manager = $self->{MB_manager}
       or return $self;

    $manager->toBeThreaded($self, @_);
    $self;
}

sub toBeUnthreaded(@)
{   my $self = shift;

    my $manager = $self->{MB_manager}
       or return $self;

    $manager->toBeThreaded($self, @_);
    $self;
}

#-------------------------------------------

=item scanForMessages MESSAGE, MESSAGE-IDS, TIMESTAMP, WINDOW

The MESSAGE which is known contains references to messages before
it which are not found yet.  But those messages can be in the same
folder.  Scan back in this folder for the MESSAGE-IDS (which may be
one string or a reference to an array of strings).  The TIMESTAMP
and WINDOW (see options in new()) limit the search.

=cut

sub scanForMessages($$$$)
{   my ($self, $startid, $msgids, $moment, $window) = @_;
    return $self unless $self->allMessages;  # empty folder.

    # Set-up window-bound.
    my $bound;
    if($window eq 'ALL')
    {   $bound = 0;
    }
    elsif(defined $startid)
    {   my $startmsg = $self->messageID($startid);
        $bound = $startmsg->nr - $window if $startmsg;
        $bound = 0 if $bound < 0;
    }

    my $last = ($self->{MBM_last} || $self->allMessages) -1;
    return $self if $bound >= $last;

    # Set-up time-bound
    my $after = $moment eq 'EVER' ? 0 : $moment;

    # Set-up msgid-list
    my %search = map {($_, 1)} ref $msgids ? @$msgids : $msgids;

    while(!defined $bound || $last >= $bound)
    {   my $message = $self->message($last);
        my $msgid   = $message->messageID;  # triggers load of head

        if(delete $search{$msgid})
        {   last unless keys %search;
        }

        last if $message->timestamp < $after;
        $last--;
    }

    $self->{MBM_last} = $last;
    keys %search;
}

#-------------------------------------------

=item sort PREPARE, COMPARE, LIST

(class method) Implements a general sort, with preparation phase.
First prepare a value foreach each element of the list by calling
the specified routine with the element as first argument.  Then
sort it based on the COMPARE routine.  In this case, the two argumements
to be compared are parsed.

=cut

sub sort(@)
{   my ($class, $prepare, $compare) = splice @_, 0, 3;
    return () unless @_;

    my %value = map { ($_ => $prepare->($_))} @_;
    sort {$compare->($value{$a}, $value{$b})} @_;
}

#-------------------------------------------

=item timespan2seconds TIME

TIME is a string, which starts with a float, and then one of the
words 'hour', 'hours', 'day', 'days', 'week', or 'weeks'.  For instance:

    '1 hour'
    '4 weeks'

=cut

sub timespan2seconds($)
{
    if( $_[1] =~ /^\s*(\d+\.?\d*|\.\d+)\s*(hour|day|week)s?\s*$/ )
    {     $2 eq 'hour' ? $1 * 3600
        : $2 eq 'day'  ? $1 * 86400
        :                $1 * 604800;  # week
    }
    else
    {   carp "Invalid timespan '$_' specified.\n";
        undef;
    }
}

#-------------------------------------------
# Instance variables
# MB_access: new(access)
# MB_alive: List of all the messages that aren't marked as deleted
# MB_body_type: new(body_type)
# MB_current: Used by some mailbox-types to save last read message.
# MB_folderdir: new(folderdir)
# MB_foldername: new(folder)
# MB_head_delayed_type: new(head_delayed_type)
# MB_head_partial_type: new(head_partial_type)
# MB_head_type: new(head_type)
# MB_init_options: A copy of all the arguments given to the constructor
# MB_is_closed: Whether or not the mailbox is closed
# MB_lazy_extract:
# MB_locker: A reference to the mail box locker.
# MB_manager: new(manager)
# MB_message_opts: ?????????????????????
# MB_messages: A list of all the messages in the folder
# MB_message_type: new(message_type)
# MB_modifications: The number of modifications made to a folder
# MB_msgid: A hash of all the messages in the mailbox, keyed on message ID
# MB_open_time: The time at which a mail box is first opened
# MB_organization: new(organization)
# MB_remove_empty: new(remove_when_empty)
# MB_save_on_exit: new(save_on_exit)
# MB_take_headers: new(take_headers)

#-------------------------------------------

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_03

=cut

1;
