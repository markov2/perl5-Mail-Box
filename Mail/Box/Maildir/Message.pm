
package Mail::Box::Maildir::Message;
use base 'Mail::Box::Dir::Message';

use strict;
use File::Copy;
use Carp;
use warnings;

=chapter NAME

Mail::Box::Maildir::Message - one message in a Maildir folder

=chapter SYNOPSIS

 my $folder = new Mail::Box::Maildir ...
 my $message = $folder->message(10);

=chapter DESCRIPTION

A C<Mail::Box::Maildir::Message> represents one message in an
M<Mail::Box::Maildir> folder. Each message is stored in a separate file.

=chapter METHODS

=method filename [FILENAME]

Returns the current filename for this message.  If the FILENAME argument
is specified, a new filename will be set.  For maildir messages this
means that modifications are immediately performed: there will be
a rename (move) from the old name to the new name.  Labels may change
within in the message object as well.

=cut

sub filename(;$)
{   my $self    = shift;
    my $oldname = $self->SUPER::filename;
    return $oldname unless @_;

    my $newname = shift;
    return $newname if defined $oldname && $oldname eq $newname;

    my ($id, $semantics, $flags)
     = $newname =~ m!(.*?)(?:\:([12])\,([A-Z]*))!
     ? ($1, $2, $3)
     : ($newname, '','');

    my %flags;
    $flags{$_}++ foreach split //, $flags;

    $self->SUPER::label
     ( draft   => ($flags{D} || 0)
     , flagged => ($flags{F} || 0)
     , replied => ($flags{R} || 0)
     , seen    => ($flags{S} || 0)
     );

    $self->SUPER::deleted($flags{T} || 0);

    if(defined $oldname)
    {   move $oldname, $newname
           or confess "Cannot move $oldname to $newname: $!";
    }

    $self->SUPER::filename($newname);
}

#-------------------------------------------

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

    $self->filename =~ m/(\d+)/ ? $1 : undef;
}

#-------------------------------------------

sub deleted($)
{   my $self = shift;
    return $self->SUPER::deleted unless @_;

    my $set  = shift;
    $self->SUPER::deleted($set);
    $self->labelsToFilename;
    $set;
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

#-------------------------------------------

=method labelsToFilename

When the labels on a message change, this may implicate a change in
the message's filename.  The change will take place immediately.

=cut

sub labelsToFilename()
{   my $self   = shift;
    my $labels = $self->labels;
    my $old    = $self->filename;

    my ($folderdir, $set, $oldname)
      = $old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$!;

    my $newflags
      = ($labels->{draft}      ? 'D' : '')    # flags must be alphabetic
      . ($labels->{flagged}    ? 'F' : '')
      . ($labels->{replied}    ? 'R' : '')
      . ($labels->{seen}       ? 'S' : '')
      . ($self->SUPER::deleted ? 'T' : '');

    my $new = File::Spec->catfile($folderdir, $set, "$oldname:2,$newflags");

    if($new ne $old)
    {   unless(move $old, $new)
        {   warn "Cannot rename $old to $new: $!";
            return;
        }
        $self->log(PROGRESS => "Moved $old to $new.");
        $self->SUPER::filename($new);
    }

    $new;
}

#-------------------------------------------

=section Internals

=method accept

Accept a message for the folder.  This will move it from the C<new> or
C<tmp> sub-directories into the C<cur> sub-directory.  When you accept an
already accepted message, nothing will happen.

=error Message $filename is not in a Maildir folder.

To accept a message into a folder (move it from a temporary location into
this folder's view), it must be already created one maildir folder's
sub-directory. When a I<foreign> message is coerce to become part of a
maildir, the coercion will create a file which is acceptable.

=cut

sub accept($)
{   my $self   = shift;
    my $old    = $self->filename;

    unless($old =~ m!(.*)/(new|cur|tmp)/([^:]*)(\:[^:]*)?$! )
    {   $self->log(ERROR => "Message $old is not in a Maildir folder.\n");
        return undef;
    }

    return $self if $2 eq 'cur';
    my $new = "$1/cur/$3";

    $self->log(PROGRESS => "Message $old is accepted.\n");
    $self->filename($new);
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
    = $info =~ m!([12])\,([RSTDF]+)$!;
 my @flags = split //, $flags;

When an application opens the folder, the message in C<new> are
inspected and moved to the C<cur> sub-directory.  Messages which were
already in that directory are considered C<old> (labelled that way inside
MailBox).  The messages are moved, and their name is immediately
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

The flags will immediately change when M<label()> or M<delete()> is used,
which differs from other message implementations: maildir is stateless,
and should not break when applications crash.

=cut

1;
