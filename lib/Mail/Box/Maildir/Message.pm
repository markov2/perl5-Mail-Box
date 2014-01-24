
use strict;
use warnings;

package Mail::Box::Maildir::Message;
use base 'Mail::Box::Dir::Message';

use File::Copy;

=chapter NAME

Mail::Box::Maildir::Message - one message in a Maildir folder

=chapter SYNOPSIS

 my $folder = new Mail::Box::Maildir ...
 my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::Maildir::Message> represents one message in an
M<Mail::Box::Maildir> folder. Each message is stored in a separate file.

=chapter METHODS

=method filename [$filename]

Returns the current filename for this message.  If the $filename argument
is specified, a new filename will be set.  For maildir messages this
means that modifications are immediately performed: there will be
a rename (move) from the old name to the new name.  Labels may change
within in the message object as well.

=cut

sub filename(;$)
{   my $self    = shift;
    my $oldname = $self->SUPER::filename();
    return $oldname unless @_;

    my $newname = shift;
    return $newname if defined $oldname && $oldname eq $newname;

    my ($id, $semantics, $flags)
     = $newname =~ m!(.*?)(?:\:([12])\,([A-Za-z]*))!
     ? ($1, $2, $3)
     : ($newname, '','');

    my %flags;
    $flags{$_}++ foreach split //, $flags;

    $self->SUPER::label
     ( draft   => (delete $flags{D} || 0)
     , flagged => (delete $flags{F} || 0)
     , replied => (delete $flags{R} || 0)
     , seen    => (delete $flags{S} || 0)
     , deleted => (delete $flags{T} || 0)

     , passed  => (delete $flags{P} || 0)    # uncommon
     , unknown => join('', sort keys %flags) # application specific
     );

    if(defined $oldname && ! move $oldname, $newname)
    {   $self->log(ERROR => "Cannot move $oldname to $newname: $!");
        return undef;
    }

    $self->SUPER::filename($newname);
}

=method guessTimestamp
The filename of a C<Mail::Box::Maildir::Message> contains a timestamp.  This
is a wild guess about the actual time of sending of the message: it is the
time of receipt which may be seconds to hours off.  But is still a good
guess...  When the message header is not parsed, then this date is used.
=cut

sub guessTimestamp()
{   my $self = shift;
    my $timestamp   = $self->SUPER::guessTimestamp;
    return $timestamp if defined $timestamp;

    $self->filename =~ m/^(\d+)/ ? $1 : undef;
}

#-------------------------------------------

=section Labels
=cut

sub label(@)
{   my $self   = shift;
    return $self->SUPER::label unless @_;

    my $return = $self->SUPER::label(@_);
    $self->labelsToFilename;
    $return;
}

=method labelsToFilename
When the labels on a message change, this may implicate a change in
the message's filename.  The change will take place immediately.  The
new filename (which may be the same as the old filename) is returned.
C<undef> is returned when the rename is required but fails.
=cut

sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $set, $oldname, $oldflags)
      = $old =~ m!(.*)/(new|cur|tmp)/(.+?)(\:2,[^:]*)?$!;

    my $newflags    # alphabeticly ordered!
      = ($labels->{draft}   ? 'D' : '')
      . ($labels->{flagged} ? 'F' : '')
      . ($labels->{passed}  ? 'P' : '')
      . ($labels->{replied} ? 'R' : '')
      . ($labels->{seen}    ? 'S' : '')
      . ($labels->{deleted} ? 'T' : '')
      . ($labels->{unknown} || '');

    my $newset = $labels->{accepted} ? 'cur' : 'new';
    if($set ne $newset)
    {   my $folder = $self->folder;
        $folder->modified(1) if defined $folder;
    }

    my $flags = $newset ne 'new' || $newflags ne '' ? ":2,$newflags"          
              : $oldflags ? ':2,' : '';                                
    my $new   = File::Spec->catfile($folderdir, $newset, $oldname.$flags);

    if($new ne $old)
    {   unless(move $old, $new)
        {   $self->log(ERROR => "Cannot rename $old to $new: $!");
            return;
        }
        $self->log(PROGRESS => "Moved $old to $new.");
        $self->SUPER::filename($new);
    }

    $new;
}

#-------------------------------------------

=section Internals

=method accept [BOOLEAN]

Accept a message for the folder.  This will move it from the C<new>
or C<tmp> sub-directories into the C<cur> sub-directory (or back when
the BOOLEAN is C<false>).  When you accept an already accepted message,
nothing will happen.

=cut

sub accept(;$)
{   my $self   = shift;
    my $accept = @_ ? shift : 1;
    $self->label(accepted => $accept);
}

#-------------------------------------------

=chapter DETAILS

=section Labels

=subsection Flags in filename

When new messages arrive on system and have to be stored in a maildir folder,
they are put in the C<new> sub-directory of the folder (first created in
the C<tmp> sub-directory and then immediately moved to C<new>).
The following information was found at L<http://cr.yp.to/proto/maildir.html>.

Each message is written in a separate file.  The filename is
constructed from the time-of-arrival, a hostname, an unique component,
a syntax marker, and flags. For example C<1014220791.meteor.42:2,DF>.
The filename must match:

 my ($time, $unique, $hostname, $info)
    = $filename =~ m!^(\d+)\.(.*)\.(\w+)(\:.*)?$!;
 my ($semantics, $flags)
    = $info =~ m!([12])\,([DFPRST]*)$!;
 my @flags = split //, $flags;

When an application opens the folder, there may be messages in C<new>
which are new arival, and messages in C<cur>.  The latter are labeled
C<accepted>.  To move a message from C<new> to C<cur>, you have two
options with the same effect:

  $msg->accept;
  $msg->label(accept => 1);

See M<accept()>, M<label()>, M<Mail::Box::Maildir::new(accept_new)>,
and M<Mail::Box::Maildir::acceptMessages()>

The messages are moved, and their name is immediately
extended with flags.  An example:

 new/897979431.meteor.42      may become
 cur/897979431.meteor.42:2,FS

The added characters C<':2,'> refer to the "second state of processing",
where the message has been inspected.  And the characters (which should
be in alphabetic order) mean

 D      => draft
 F      => flagged
 R      => replied  (answered)
 S      => seen
 T      => deleted  (tagged for deletion)

Some maildir clients support
 P      => passed   (resent/forwarded/bounced to someone else)

The flags will immediately change when M<label()> or M<delete()> is used,
which differs from other message implementations: maildir is stateless,
and should not break when applications crash.

=cut

1;
