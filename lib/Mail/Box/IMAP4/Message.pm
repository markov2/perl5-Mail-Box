
use strict;
use warnings;

package Mail::Box::IMAP4::Message;
use base 'Mail::Box::Net::Message';

use Date::Parse 'str2time';

=chapter NAME

Mail::Box::IMAP4::Message - one message on a IMAP4 server

=chapter SYNOPSIS

 my $folder = new Mail::Box::IMAP4 ...
 my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::IMAP4::Message> represents one message on a IMAP4 server,
maintained by a M<Mail::Box::IMAP4> folder. Each message is stored as
separate entity on the server, and maybe temporarily in your program
as well.

=chapter METHODS

=c_method new %options

=default body_type M<Mail::Message::Body::Lines>

=option  write_labels BOOLEAN
=default write_labels <true>
When a label is changed or its value read, using M<label()>, that info
should be sent to the IMAP server.  But, this action could be superfluous,
for instance because the label was already set or clear, and communication
is expensive.  On the other hand, someone else may use IMAP to make
changes in the same folder, and will get the updates too late or never...

=option  cache_labels BOOLEAN
=default cache_labels <false>
All standard IMAP labels can be cached on the local server to improve
speed.  This has the same dangers as setting C<write_labels> to false.
The caching starts when the first label of the message was read.

=option  cache_head BOOLEAN
=default cache_head <false>

=option  cache_body BOOLEAN
=default cache_body <false>

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{MBIM_write_labels}
       = exists $args->{write_labels} ? $args->{write_labels} : 1;

    $self->{MBIM_cache_labels} = $args->{cache_labels};
    $self->{MBIM_cache_head}   = $args->{cache_head};
    $self->{MBIM_cache_body}   = $args->{cache_body};

    $self;
}

=method size
Returns the size of this message.  If the message is still on the remote
server, IMAP is used to ask for the size.  When the message is already loaded
onto the local system, the size of the parsed message is taken.  These
sizes can differ because the difference in line-ending representation.
=cut

sub size($)
{   my $self = shift;
    
    return $self->SUPER::size
        unless $self->isDelayed;

    $self->fetch('RFC822.SIZE');
}

sub recvstamp()
{   my $date = shift->fetch('INTERNALDATE');
    defined $date ? str2time($date) : undef;
}

=method label $label|PAIRS
With only one argument, the value related to $label is returned.  With
more that one argument, the list is interpreted a label-value PAIRS
to be set.

The IMAP protocol defines its own names for the labels, which must
be set imediately to inform other IMAP clients which may have the
same folder open. But that can be changed with M<new(write_labels)>.
Some labels are translated to the corresponding IMAP system labels. 

=cut

sub label(@)
{   my $self = shift;
    my $imap = $self->folder->transporter or return;
    my $id   = $self->unique or return;

    if(@_ == 1)
    {   # get one value only
        my $label  = shift;
        my $labels = $self->{MM_labels};
	return $labels->{$label}
	    if exists $labels->{$label} || exists $labels->{seen};

	my $flags = $imap->getFlags($id);
        if($self->{MBIM_cache_labels})
	{   # the program may have added own labels
            @{$labels}{keys %$flags} = values %$flags;
            delete $self->{MBIM_labels_changed};
	}
	return $flags->{$label};
    }

    my @private;
    if($self->{MBIM_write_labels})
    {    @private = $imap->setFlags($id, @_);
         delete $self->{MBIM_labels_changed};
    }
    else
    {    @private = @_;
    }

    my $labels  = $self->{MM_labels};
    my @keep    = $self->{MBIM_cache_labels} ? @_ : @private;

    while(@keep)
    {   my ($k, $v) = (shift @keep, shift @keep);
        next if defined $labels->{$k} && $labels->{$k} eq $v;

        $self->{MBIM_labels_changed}++;
        $labels->{$k} = $v;
    }
    $self->modified(1) if @private && $self->{MBIM_labels_changed};
 
    $self;
}

=method labels
Get the names of all labels (LIST context, not efficient in IMAP4), or
a reference to a hash with labels.  You should only use the returned
hash to read the labels, because changes made to it will not be passed
to the remote server.  See M<labels()> to set values.
=cut

sub labels()
{   my $self   = shift;
    my $id     = $self->unique;
    my $labels = $self->SUPER::labels;
    $labels    = { %$labels } unless $self->{MBIM_cache_labels};

    if($id && !exists $labels->{seen})
    {   my $imap = $self->folder->transporter or return;
        my $flags = $imap->getFlags($id);
        @{$labels}{keys %$flags} = values %$flags;
    }

    $labels;
}

#-------------------------------------------

=section Internals

=cut

sub loadHead()
{   my $self     = shift;
    my $head     = $self->head;
    return $head unless $head->isDelayed;

    $head         = $self->folder->getHead($self);
    $self->head($head) if $self->{MBIM_cache_head};
    $head;
}

sub loadBody()
{   my $self     = shift;

    my $body     = $self->body;
    return $body unless $body->isDelayed;

    (my $head, $body) = $self->folder->getHeadAndBody($self);
    return undef unless defined $head;

    $self->head($head)      if $self->{MBIM_cache_head} && $head->isDelayed;
    $self->storeBody($body) if $self->{MBIM_cache_body};
    $body;
}

=method fetch [$info, ...]
Use the IMAP's C<UID FETCH IMAP> command to get some data about this
message.  The $info request is passed to M<Mail::Box::IMAP4::fetch()>.
Without $info, C<ALL> information is retrieved and returned as a HASH.
=cut

sub fetch(@)
{   my ($self, @info) = @_;
    my $folder = $self->folder;
    my $answer = ($folder->fetch( [$self], @info))[0];

    @info==1 ? $answer->{$info[0]} : @{$answer}{@info};
}

=method writeDelayed $imap
Write all delayed information, like label changes, to the server.  This
is done under force, so should even be done for folders opened without
write-access. This method is called indirectly by a M<Mail::Box::write()>
or M<Mail::Box::close()>.

The $imap argument is a M<Mail::IMAPClient> which has the right folder
already selected.

Writing changes to the remote folder is not without hassle: IMAP4
(or is it only L<Mail::IMAPClient> doesn't support replacing header
or body.  Therefore, when either of them change, the whole message is
rewritten to the server (which is supported), and the original flagged
for deletion.

=cut

sub writeDelayed($$)
{   my ($self, $foldername, $imap) = @_;

    my $id     = $self->unique;
    my $labels = $self->labels;

    if($self->head->modified || $self->body->modified || !$id)
    {
        $imap->appendMessage($self, $foldername);
        if($id)
        {   $self->delete;
            $self->unique(undef);
        }
    }
    elsif($self->{MBIM_labels_changed})
    {   $imap->setFlags($id, %$labels);  # non-IMAP4 labels disappear
        delete $self->{MBIM_labels_changed};
    }

    $self;
}

#-------------------------------------------

=chapter DETAILS

=section Labels

=subsection IMAP protocol flags

Labels (or flags) are known to all folder formats, but differ how they
are stored.  Some folder types use message header lines to keep the
labels, other use a separate file.  The IMAP protocol does not specify
how the labels are kept on the server, but does specify how they are named.

The label names as defined by the IMAP protocol are standardized into
the MailBox standard to hide folder differences.  The following translations
are always performed:

 \Seen     => seen
 \Answered => replied
 \Flagged  => flagged
 \Deleted  => deleted
 \Draft    => draft
 \Recent   => NOT old

=examples of label translations

 $imap->message(3)->label(replied => 1, draft => 0);

will result in a IMAP protocol statements like

 A003 STORE 4 +FLAGS (\Answered)
 A003 STORE 4 -FLAGS (\Draft)

=subsection Other labels

Of course, your program may be in need for more labels than those provided
by the protocol.  You can still use these: they stay locally (and are
lost when the folder is closed).  Some IMAP4 extensions permit more labels
than the basic RFC, but that is not yet supported by this implementation.

=subsection Caching labels

When you ask for one or more flags of a message more than once, you may
improve the overall performance by setting M<new(cache_labels)> to C<YES>.
However, this may cause inconsistencies when multiple clients use the
same folder on the IMAP server.

You may also delay the label updates to the server until the
folder is closed (or for ever when read-only is required).  When
M<Mail::Box::write()> or M<Mail::Box::close()> is called, it is decided
whether to throw all changes away or write after all.

=cut

1;
