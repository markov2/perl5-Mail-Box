
package Mail::Box;
#use 5.006;

$VERSION = '1.300';

use Carp;
use MIME::Parser;

use Mail::Box::Message;
use Mail::Box::Locker;

use strict;

=head1 NAME

Mail::Box - Manage a message-folder.

=head1 SYNOPSIS

   use Mail::Box;
   my $folder = new Mail::Box::Mbox folder => $ENV{MAIL}, ...;
   print $folder->message(0)->head->get('subject');  # See Mail::Box::Message
   $folder->message(3)->deleted(1);
   my $emails = $folder->messages;          # amount

   $folder->addMessage(new Mail::Box::Message(...));

   foreach ($folder->messages) {...}        # the messages
   foreach (@$folder) {...}                 # same

Tied-interface:

   use Mail::Box;
   my $mgr   = new Mail::Box::Manager;
   my $inbox = $mgr->open(folder => '/tmp/inbox');
   
   tie my(@inbox), 'Mail::Box::Tie::ARRAY', $inbox;
   $inbox[3]->print        # equiv to $folder->message(3)->print
   tie my(%inbox), 'Mail::Box::Tie::HASH', $inbox;
   $inbox{$msgid}->print   # equiv to $folder->messageID($msgid)->print
   # See Mail::Box::Tie


=head1 DESCRIPTION

Read Mail::Box::Manager first.
Mail::Box is the base-class for accessing various types of mail-folder
organizational structures in a uniformal way.

The various folder-types do vary on how they store their messages (a
folder with many messages in a single file or a folder as a directory
with each message in a single file)  Furthermore, different types of
folders have different ways to be locked.

Applications usually add information to the messages in the folders, for
instance whether you have replied to a message or not.  The base-class
for messages in a folder is Mail::Box::Message (an extention of
MIME::Entity).  It presents message-facts in an application-independent
way.  Each application needs to extend Mail::Box::Message with their own
practices.

=head1 METHODS

=over 4

=item new ARGS

(Class method) Open a new folder.  The ARGS is a list of labeled parameters
defining what to do.  Each sub-class of Mail::Box will add different
options to this method.  See their manual-pages.

All possible options are:  (for detail description of the Mail::Box
specific options see below, for the other options their respective
manual-pages)

 access            Mail::Box          'r'
 create            Mail::Box          0
 folder            Mail::Box          $ENV{MAIL}
 folderdir         Mail::Box          <no default>
 lazy_extract      Mail::Box          10kb
 lock_file         Mail::Box::Locker  foldername.'.lock'
 lock_method       Mail::Box::Locker  'DOTLOCK'
 lock_timeout      Mail::Box::Locker  1 hour
 lock_wait         Mail::Box::Locker  10 seconds
 manager           Mail::Box          undef
 message_type      Mail::Box          'Mail::Box::Message::Parsed'
 notreadhead_type  Mail::Box          'Mail::Box::Message::NotReadHead'
 notread_type      Mail::Box          'Mail::Box::Message::NotParsed'
 organization      Mail::Box          'FILE'
 realhead_type     Mail::Box          'MIME::Head'
 remove_when_empty Mail::Box          1
 save_on_exit      Mail::Box          1
 take_headers      Mail::Box          <specify everything you need>
 <none>            Mail::Box::Tie

The options added by Mail::Box

=over 4

=item * folder =E<gt> FOLDERNAME

Which folder to open (for read or write).  When used for reading (the
C<access> option set to C<"r">) the mailbox should already
exist.  When opened for C<"rw">, we do not care, although write-permission
is checked on opening.

=item * access =E<gt> MODE

Access-rights to the folder. MODE can be read-only (C<"r">), append (C<"a">),
and read-write (C<"rw">).  These modes have nothing in common with the modes
actually used to open the folder-files within this module.

Folders are opened for read-only (C<"r">) by default.

=item * folderdir =E<gt> DIRECTORY

Where are folders written by default?  You can specify a folder-name
preceeded by C<=> to explicitly state that the folder is located below
this directory.

=item * message_type =E<gt> CLASS

What kind of message-objects are stored in this type of folder.  The
default is Mail::Box::Message (which is a sub-class of MIME::Entity).
The class you offer must be an extention of Mail::Box::Message.

=item * organization =E<gt> 'FILE' | 'DIRECTORY'

Tells whether a folder is one file containing many messages (like Mbox-folders) or one directory per folder, a message per file (like MH-folders).

=item * save_on_exit =E<gt> BOOL

Sets the default on what to do when the folder is closed (see the
C<close()> method.  When the program is terminated, or any other
reason when the folder is automatically close, this flag determines
what to do.  By default, this is TRUE;

=item * remove_when_empty =E<gt> BOOL

Remove the folder-file or directory (dependent on the type of folder)
automatically when the write would result in a folder without sub-folders
and messages.  This is true by default.

=item * manager =E<gt> MANAGER

The object which manages this folder.  Typically a (sub-class of)
Mail::Box::Manager.

=back

Some folder-types have the following options.  You can find this
in their specific manual-pages.  Folders which do not support these
fields will not complain.

=over 4

=item * notread_type =E<gt> CLASS

=item * notreadhead_type =E<gt> CLASS

=item * realhead_type =E<gt> CLASS

Three classes of objects which are usually hidden for users of this
module, but especially useful if you plan to extent modules.  These
classes all contain parts of an incompletely read message.

=item * lazy_extract =E<gt> INTEGER

=item * lazy_extract =E<gt> CODE

=item * lazy_extract =E<gt> METHOD

=item * lazy_extract =E<gt> 'NEVER'|'ALWAYS'

If you supply a number to this option, bodies of those messages with a
total size less than that number will be extracted from the folder only
when nessesary.  Headers will always be extracted, even from the larger
messages.  This reduces the memory-footprint of the program, with only
little cost.

When you supply a code-reference, that subroutine is called every time
that the extraction mechanism wants to determine whether to parse the
body or not. The subroutine is called:

    $code->(FOLDER, HEADER, BODY, BYTES)

where FOLDER is a reference to the folder we are reading.  HEADER refers
an array of header-lines, or a MIME::Header, but may also be C<undef>.  You
have to handle all three situations.
BODY refers to the array lines which form the body of the message (including
message-parts), but may also be C<undef>, dependent on the folder-type.
BYTES is the size of the message in bytes including the header-lines, and
always defined.  This may be the best way to make a selection.

The routine must return true (be lazy: delay extract) or false (extract
now).

The third possibility is to specify the NAME of a method.  In that case,
for each message is called:

   FOLDER->NAME(HEADER, BODY, BYTES)

Where each field has the same meaning as described above.

The fourth way to use this parameter involves constants: with C<'NEVER'>
you can disable delayed loading.    With C<'ALWAYS'> you force unconditional
delayed-loading.

Examples:

    $folder->new(lazy_extract => 'NEVER');
    $folder->new(lazy_extract => 10000);
    $folder->new(lazy_extract => sub {$_[3] >= 10000 }); #same

    $folder->new(lazy_extract => 'sent_by_me');
    sub Mail::Box::send_by_me($$$)
    {   my ($self, $header, $lines, $bytes) = @_;
        $header->get('from') =~ m/\bmy\@example.com\b/i;
    }

The Mail::Box::Message manual-page has more on this subject.

=item * take_headers =E<gt> ARRAY-REGEXPS|REGEXP|'ALL'|'REAL'|'DELAY'

When messages are not parsed (as controlled by the C<lazy_extract> parameter),
and hence stay in their respective folders, some header-lines are still to be
taken: for instance you still want access to the subject-field to be able
to print an index.

See C<registerHeaders()> below, for a detailed explanation.  Please try
to avoid calling that method when you can do with using this option.

Examples:

   $folder->new( take_headers  => 'ALL');
   $folder->new( take_headers  => 'Subject');
   $folder->new( take_headers  =>
         [ 'X-Mutt-.*', 'X-Folder-.*' ]);
   $folder->new( take_headers  => 'REAL'
               , realhead_type => 'MIME::Head'
               );

=back

=cut

use overload '@{}' => 'as_row';
use overload '""'  => 'name';
use Carp;
use overload 'cmp' => sub {$_[0]->name cmp $_[1]->name};

sub new(@)
{   my $class   = shift;

    if($class eq __PACKAGE__)
    {   use Carp;
        my $package = __PACKAGE__;
        croak <<USAGE;
You should not instantiate $package but one of the sub-classes, like
Mail::Box::Mbox.  If you need folder-type autodetection, then use
the folder-manager (see Mail::Box::Manager).
USAGE
    }

    my $self    = bless {}, $class;

    $self->{MB_init_options} = [ @_ ];  # for clone
    my %args    = @_;

    $self->init(\%args) or return;
    $self->read         or return if $self->readable;

    $self;
}

sub init($)
{   my ($self, $args) = @_;
    my $class = ref $self;

    unless(defined $args->{folder})
    {   warn "No folder specified.\n";
        return;
    }

    $self->{MB_message_opts} = $args->{message_options}   || [];
    delete $args->{message_options};

    $self->{MB_foldername}   = $args->{folder}            || $ENV{MAIL};
    $self->{MB_access}       = $args->{access}            || 'r';
    $self->folderdir($args->{folderdir});

    $self->{MB_remove_empty} = $args->{remove_when_empty} || 1;
    $self->{MB_messages}     = [];
    $self->{MB_modifications}= 0;
    $self->{MB_save_on_exit} = $args->{save_on_exit}      || 1;
    $self->{MB_organization} = $args->{organization}      || 'FILE';
    $self->{MB_manager}      = $args->{manager}
        if exists $args->{manager};

    my $message_type         = $self->{MB_message_type}
        = $args->{message_type}     || $class . '::Parsed';
    $self->{MB_notreadhead_type}
        = $args->{notreadhead_type} || $class . '::NotReadHead';
    $self->{MB_notparsed_type}
        = $args->{notparsed_type}   || $class . '::NotParsed';
    $self->{MB_realhead_type}
        = $args->{realhead_type}    || 'MIME::Head';

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

See the C<take_header> option of C<new()>, which is the prefered way
to specify which way the header should be treated.  Try to avoiding
C<registerHeaders> directly.

The C<registerHeaders> method can be used to specify more header-lines
to be taken when scanning through a folder.  Its counterpart
C<registeredHeaders> returns the current setting.

If you know your application needs some header-fields frequently, you
add them to the default list of fields which are already taken by the
folder-implementation.  No problem if you specify the same name twice.

If you specify too few field-names, then all messages will get parsed
(read from file into memory) to get the field-data you missed.  When you
specify too many fields, your program will consume considerable more memory.

You can specify a regular expression, although you cannot use parentheses
in them which do count.  The expressions will be matched always on the
whole field.  So C<X-.*> will only match lines starting with
C<X->.
You can not used C<X-(ab|cd).*>,
but may say C<X-(?:ab|cd).*>.

There are three special constants.  With C<ALL> you get all header-lines
from the message (same as pattern C<.*>)  and C<REAL> will cause headers
to be read into a real MIME::Header structure (to be more precise: the
type you specify with C<realhead_type>.)

Some folder-types (like MH) support C<DELAY>, where headers are to taken
at all, until a line from the header is required.  This is useful for
folders where each message has to be read from a seperate source.  In
this case, we would like to delay even that contact as long as possible.

=over 4

=item * 'ALL' to indicate that all headers should be taken.

=item * 'REAL'

indicates that all headers should be taken and translated into a
real MIME::Header.

=item * 'DELAY'

requests for no header at all, unless we accidentally stumble on them.  This
is default (and only usefull) for all folder-types which store their
messages in seperate files.  Mail::Box will try to avoid opening those
files with maximum effort.

In case you need header-lines, and at the same time want to avoid access
to each file when a folder is opened (for instance, if you want to read
e-mail in threads), consider using index-files.  Read the manual-page of
the folder-type you need on whether those is supported for that specific
type.

=item * a list of regular expressions

which specify the header-lines to be taken.

=back

Examples:

   $folder->registerHeaders('ALL');
   $folder->registerHeaders('Subject', 'X-Folder-.*');

=cut

sub registerHeaders(@)
{   my $self = shift;

    if(grep {$_ eq 'REAL'} @_)
    {   $self->{MB_take_headers} = 'REAL';
    }
    elsif(grep {$_ eq 'DELAY'} @_)
    {   $self->{MB_take_headers} = 'DELAY';
    }
    elsif(exists $self->{MB_take_headers} && !ref $self->{MB_take_headers})
    {  # Already an important constant defined: no change to be made.
    }
    elsif(grep {$_ eq 'ALL' || $_ eq '^.*$'} @_)
    {   $self->{MB_take_headers} = 'ALL';
    }

    elsif(exists $self->{take_headers} && !ref $self->{take_headers})
    {   # Detected a REAL or ALL before.  Don't need to register more.
    }
    else { map {$self->{MB_take_headers}{lc $_}++} @_ }

    $self;
}

sub registeredHeaders() { shift->{MB_take_headers} }

#-------------------------------------------

=item unfoldHeaders REF-ARRAY

E-mail headers may span a few lines (I<folded> fields).  The first line
has the name of the field, and is followed by one or more lines which
start with some blanks.

This method receives an array, and modifies it such that folder lines
are rejoined with their field-name.  Don't forget to fold back again
when printing to file.

=cut

sub unfoldHeaders($)
{   my ($self, $headers) = @_;

    for(my $h=1; $h<@$headers; $h++)
    {   next unless $headers->[$h] =~ m/^\s+/;

        chomp $headers->[$h-1];
        $headers->[$h-1] .= ' ' . $';
        splice @$headers, $h, 1;
        redo if $h<@$headers;
    }
}

#-------------------------------------------

=item read OPTIONS

Read messages from the folder into the folder-structure.  If there
are already messages in this structure, the new ones are added.

When to want to add messages from a different foldertype to this folder,
you need to join folders, as shown in the following example.

Example read folder into folder:

   my $folder = Mail::Box::File->new(folder => 'InBox');
   my $old    = Mail::Box::MH->new(folder => 'Received');
   $folder->addMessages(@$old);
   $folder->write;
   $old->delete;

=cut

sub read(@)
{   my $self = shift;
    $self->{MB_open_time}  = time;

    # Read from existing folder.
    return $self if $self->readMessages(@_);
}

#-------------------------------------------

=item write [OPTIONS]

Write the data to disk.  It returns the folder when this succeeded.  If you
want to write to a different file, you first create a new folder, then
move the messages, and then write that file.

As options you may specify

=over 4

=item * force =E<gt> BOOL

Overrule write-protection (if possible, it may still be blocked by the
operating-system).

=item * keep_deleted =E<gt> BOOL

Do not remove messages which were flaged to be deleted from the folder,
but do remove them from disk.

=item * save_deleted =E<gt> BOOL

Save messages which where flagged to be deleted.  The flag is conserved
(when possible)

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
                if($message->headIsRead)
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

Close the folder.  It depends on the OPTIONS whether the folder is
to be written or not.  Futhermore, you may specify options which
are passed to C<write>, as descibed above.

Options specific to C<close> are:

=over 4

=item * write =E<gt> 'ALWAYS'|'NEVER'|'MODIFIED'

When must the folder be written.  As could be expected, C<'ALWAYS'> means
always (even if there are no changes), C<'NEVER'> means that changes to
the folder will be lost, and C<'MODIFIED'> (which is the default) only
saves the folder if there are any changes.

=item * force =E<gt> BOOL

Overrule the setting of C<access> when the folder was opened.  This only
contributes to your program when you give it a TRUE value.  However: writing
to the folder not be permitted by the file-system, in which case even
C<force> will not help.

=back

=cut

sub close(@)
{   my ($self, %args) = @_;
    my $force = $args{force} || 0;

    return if exists $self->{MB_is_closed};
    $self->{MB_is_closed} = 1;

    # Inform manager that the folder is closed.
    $self->{MB_manager}->close($self)
        if exists $self->{MB_manager};

    my $write
      = !exists $args{write} || $args{write} eq 'MODIFIED' ? $self->modified
        : $args{write} eq 'ALWAYS'                         ? 1
        : $args{write} eq 'NEVER'                          ? 0
        :                                                    0;

    if($write && !$force && !$self->writeable)
    {   warn "No changes made to read-only folder.\n";
        return 1;
    }

    my $rc = $write
           ? $self->write(force => $force)
           : 1;

    $self->{MB_locker}->unlock;
    undef $self;
    $rc;
}

#-------------------------------------------

=item delete

Remove the specified folder-file or folder-directory (dependent on
the type of folder) from disk.  Of course, THIS IS DANGEROUS: you "may"
lose data.

When you first copied this folder's information into an other folder, then be
sure that that folder is written to disk first!  Otherwise you may loose data
in case of a system-crash or software problems.

Examples of instance call:

   my $folder = Mail::Box::File->new(folder => 'InBox');
   $folder->delete;

=cut

sub delete()
{  # Extra protection: do not remove read-only folders.
    my $self = shift;

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

=item name

Returns the name of this folder.  What the name represents depends on
the actual type of mailboxes used.

Example:

   print $folder->name;

=cut

sub name() { shift->{MB_foldername} }

#-------------------------------------------

=item writeable

=item readable

Checks whether the current folder is writeable respectively readable.

Example:

    $folder->addMessage($msg) if $folder->writeable;

=cut

sub writeable() { shift->{MB_access} =~ /w|a/ }
sub readable()  { shift->{MB_access} =~ /r/ }

#-------------------------------------------

=item modified

=item modifications INCR

C<modified> checks if the folder is modified, where C<modifications> is
used to tell the folder how many changes are made in messages.  The
INCR value can be negative to undo effects.

=cut

sub modified($)      { shift->{MB_modifications} }
sub modifications($) { shift->{MB_modifications} += shift }

#-------------------------------------------

=item lazyExtract HEADER, BODY, BYTES

Calls the subroutine which will perform the chech whether a message's
body should be extracted or stay in the folder until used.  This
method calls the routine defined by the `lazy_extract' option at
creation of the folder.

=cut

sub lazyExtract($$$)
{   my $self = shift;
    $self->{MB_lazy_extract}->($self, @_);
}

#-------------------------------------------

=item message INDEX

Get or set a message with on a certain index.  Negative indexes
start at the end of the folder.

Examples:

    my $msg = $folder->message(3);
    $folder->message(3)->delete;   # status changes to `deleted'
    $folder->message(3) = $msg;
    print $folder->message(-1);    # last message.

=cut

sub message(;$)
{   my Mail::Box $self = shift;
    $self->{MB_messages}[shift];
}

#-------------------------------------------

=item organization

Return whether a folder is organized as one 'FILE' with many messages or
a 'DIRECTORY' with one message per file.

=cut

sub organization() { shift->{MB_organization} }

#-------------------------------------------

=item messageID MESSAGE-ID [,MESSAGE]

Returns the message in this folder with the specified MESSAGE-ID.  This
method returns a not-parsed, parsed, or dummy message.  With the second
MESSAGE argument, the value is first set.

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

=item messages

Returns all messages which are I<not> scheduled to be deleted.  In
scalar context, it provides you with the number of undeleted
messages in this folder.  Dereferencing a folder to an array is
overloaded to call this method.

Examples:

    foreach ($folder->messages) {...}
    foreach (@$folder)
    my $remaining_size = $folder->messages;

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
those which are to be deleted.

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
to be read.  See their respective manual-pages.

Examples:

    foreach my $id ($folder->allMessageIDs)
    {   $folder->messageID($id)->print;
    }

=cut

sub allMessageIDs() { keys %{shift->{MB_msgid}} }

#-------------------------------------------

=item addMessage  MESSAGE

=item addMessages MESSAGE [, MESSAGE, ...]

Add a message to the folder.  A message is usually a Mail::Box::Message
object or a sub-class of that.

Messages with id's which allready exist in this folder are neglected.

Examples:

   $folder->addMessage($msg);
   $folder->addMessages($msg1, $msg2, ...);

=cut

sub addMessage($)
{   my $self    = shift;
    my $message = shift or return $self;

    push @{$self->{MB_messages}}, $message;

    push @{$self->{MB_alive}}, $message
        unless $message->deleted || !exists $self->{MB_alive};

    $message->seqnr( @{$self->{MB_messages}} -1);

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
foldertype is checked.
 
This method gets a list of labeled parameters, which may contain
any flag which can be used when a folder is opened (most importantly
C<folderdir>).  Next to these, two parameters shall be specified:

=over 4

=item * folder =E<gt> FOLDERNAME

The name of the folder where the messages are to be appended.  When possible,
the folder-implementation will avoid to open the folder for real, because
that is resource consuming.

=item * message =E<gt> MESSAGE

=item * messages =E<gt> ARRAY-OF-MESSAGES

One reference to a MESSAGE or a reference to an ARRAY of MESSAGEs, which may
be of any type.  The messages will first be coerced into the correct
message-type to fit in the folder, and then be added to it.

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

Signals to the folder that a message has been deleted.  This method is
called automatically when you call the C<delete> method on a MESSAGE.  If
the BOOL is true, the message got deleted, otherwise it got undeleted.

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

=item current [NR|MESSAGE|MESSAGE-ID]

Returns the current message (when specified, after setting it to a new
values.  You may specify a NUMBER, to specify that that message-number
is to be selected as current, or a MESSAGE/MESSAGE-ID (as long as you
are sure that the header is already loaded, otherwise they are not
recognized).

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

This method is called by Perl when an folder-object is not accessible
anymore by the rest of the program.  However... This is not accomplished
automatically because (unparsed) messages reference back to their folder:
there is a two-way reference which is not resolved by the perl-memory
cleanup.

The two ways to clean-up the folder information is

=over 4

=item * by explicitly call for a C<close> on a folder,

in which case the data may be preserved (when the C<save_on_exit> flag
was selected), or

=item * by terminating the program

which will cause changes to be lost.  In this condition, the two-way
reference will cause Perl to call the DESTROY of the folder and its
messages in undefined order.  It is not possible to write messages
which are already removed...

=back

=cut

sub DESTROY
{   my $self = shift;

    # It is not possible to close the folder here nicely, because the
    # final cleanup round of objects, on the moment that perl shuts-down
    # calls DESTROY in unpredicatable order.  Folders refer to messages,
    # and messages refer to their folders.  Tried a lot, but cannot solve
    # this until the garbage-collection of Perl changes.

    # If you use the Mail::Box::Manager, you should never get this message
    # because that `END' will close all folders first.

    warn "Changes to folder `", $self->name, "' not written.\n"
       if !$self->{MB_is_closed} && $self->modified && $self->writeable;

    # Remove internal references to accomplish memory-cleanup.
    undef $self->{MB_messages};

    # The folder-locks will autodestruct.

    $self;
}

#-------------------------------------------

=back

=head2 folder management methods

The following class methods are used to test and list folders.  The do
share the C<folderdir> option, where you can specify which is the default
location for the folder-files.

=over 4

=item foundIn FOLDERNAME [,OPTIONS]

(class method) Autodetect if there is a folder of a certain
type specified here.  This method is extended for each type of
folder.

The FOLDERNAME specifies the name of the folder, as is specified by the
application.  OPTIONS is a list of extra information on the request.
Read the manual-page for each type of folder for more options, but at
least each type will support

=over 4

=item * folderdir =E<gt> DIRECTORY

The location where the folders of this class are stored by default.  If the
user specifies a name starting with a C<=>, that symbolizes that the
name is to be found is this default DIRECTORY.

=back

=cut

sub foundIn($@)
{   my ($class, $folder, @options) = @_;
    die "$class could not autodetect type of $folder.";
}

#-------------------------------------------

=item create FOLDERNAME [, OPTIONS]

(Class method) Create a folder.  If the folder already exists, it will
be left untouched.  As options, you may specify:

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

(Class and Instance method) List all folders which belong to a certain class of
folders.  Each class shall extent this method.  As class method, the C<folder>
option is usually used (defaults to the top folderdir).  This method will return
the sub-folders of the opened folder when called as instance method.

At least the following options are supported, but refer to the manpage
of the various folder-classes to see more options.

=over 4

=item * folder =E<gt> FOLDERNAME

The folder of which the sub-folders should be listed.

=item * folderdir =E<gt> DIRECTORY

=item * check =E<gt> BOOL

Specifies whether to do a very thorrow job on selecting folders.  Performing
a check on each file or directory (depends on the type of folder) to see if
it really contains a folder can be time-consuming, so the default is off.

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

#---- convenience methods for accessing MIME::Parser

sub parser()
{   my $self = shift;
    return $self->{MB_parser} if exists $self->{MB_parser};

    my $parser = new MIME::Parser;
#   $parser->output_dir($ENV{TMPDIR} || '/tmp');
#   $parser->output_prefix(__PACKAGE__);
    $parser->output_to_core('ALL');
#   $parser->interface(ENTITY_CLASS => $self->{MB_message_type});

    $parser->decode_headers(0);
    $parser->extract_nested_messages(1);
    $parser->extract_uuencode(1);
    $parser->ignore_errors(0);
    $self->{MB_parser} = $parser;
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

# toBeThreaded MESSAGES
# toBeUnthreaded MESSAGES
#
# The specified message is ready to be included in (or remove from) a thread.
# This will be passed on to the mail-manager, which keeps an overview on
# which thread-detection objects are floating around.

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

# scanForMessages MESSAGE, MESSAGE-IDS, TIMESTAMP, WINDOW
#
# The MESSAGE which is known contains references to messages before
# it which are not found yet.  But those messages can be in the same
# folder.  Scan back in this folder for the MESSAGE-IDS (which may be
# one string or a reference to an array of strings).  The TIMESTAMP
# and WINDOW (see options in new()) limit the search.
#

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

# sort PREPARE, COMPARE, LIST
#
# (class method) Implements a general sort, with preparation phase.
# First prepare a value foreach each element of the list by calling
# the specified routine with the element as first argument.  Then
# sort it based on the COMPARE routine.  In this case, the two argumements
# to be compared are parsed.

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

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 1.300

=cut

1;
