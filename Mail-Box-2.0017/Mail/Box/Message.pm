
use strict;

package Mail::Box::Message;
use base 'Mail::Message';

use Date::Parse;
use Scalar::Util 'weaken';

our $VERSION = 2.00_17;

=head1 NAME

Mail::Box::Message - Manage one message within a mail-folder

=head1 CLASS HIERARCHY

 Mail::Box::Message
 is a Mail::Message + ::Construct
 is a Mail::Reporter

=head1 SYNOPSIS

 # Usually these message objects are created indirectly
 use Mail::Box::Manager;
 my $manager = Mail::Box::Manager->new;
 my $folder  = $manager->open(folder => 'Mail/Drafts');
 my $msg     = $folder->message(1);
 $msg->delete;
 $msg->size;   # and much more

=head1 DESCRIPTION

These pages do only describe methods which relate to folders.  If you
access the knowledge of a message, then read C<Mail::Message>.

During its life, a message will pass through certain stages.  These
stages were introduced to reduce the access-time to the folder.  Changing
from stage, the message's body and head objects may change.

The bottom of this page provides more
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Message> objects:

  MMC bounce OPTIONS                    MM modified [BOOL]
  MMC build [MESSAGE|BODY], CONTENT        new OPTIONS
  MMC buildFromBody BODY, HEADERS       MM nrLines
      copyTo FOLDER                     MM parent
   MM decoded OPTIONS                   MM parts
      delete                            MM print [FILEHANDLE]
      deleted [BOOL]                   MMC quotePrelude [STRING|FIELD]
   MM encode OPTIONS                   MMC reply OPTIONS
   MR errors                           MMC replySubject STRING
      folder [FOLDER]                   MR report [LEVEL]
   MM get FIELD                         MR reportAll [LEVEL]
   MM guessTimestamp                    MM send [MAILER], OPTIONS
   MM isDummy                              seqnr [INTEGER]
   MM isMultipart                          setLabel LIST
   MM isPart                               shortString
      label STRING [ ,STRING ,...]      MM size
      labels                            MM timestamp
   MR log [LEVEL [,STRINGS]]            MM toplevel
   MM messageId                         MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MM isDelayed
   MM DESTROY                           MR logPriority LEVEL
   MM body [BODY]                       MR logSettings
   MM clone                             MR notImplemented
   MM coerce MESSAGE                    MM read PARSER, [BODYTYPE]
      diskDelete                           readBody PARSER, HEAD [, BO...
   MM head [HEAD]                       MM readHead PARSER [,CLASS]
   MR inGlobalDestruction               MM storeBody BODY

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MMC = L<Mail::Message::Construct>

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Initialize the runtime variables of a message.  The following options
are supported:

 OPTION        DESCRIBED IN         DEFAULT
 body          Mail::Message        undef
 body_type     Mail::Box::Message   <from folder>
 deleted       Mail::Box::Message   0
 folder        Mail::Box::Message   <required>
 head          Mail::Message        undef
 head_type     Mail::Message        'Mail::Message::Head::Complete'
 head_wrap     Mail::Message        72
 labels        Mail::Box::Message   []
 log           Mail::Reporter       'WARNINGS'
 messageId     Mail::Message        undef
 modified      Mail::Message        0
 size          Mail::Box::Message   undef
 trace         Mail::Reporter       'WARNINGS'
 trusted       Mail::Message        0


=over 4

=item * folder =E<gt> FOLDER

(obligatory) The folder where this message appeared in.  The argument is
an instance of (a sub-class of) a Mail::Box.

=item * body_type =E<gt> CODE|CLASS

If the body of a message is used delay-loaded, the message must what type
of message to become when it finally gets parsed.  The folder which is
delaying the load must specify the algorithm to determine that type.  See
C<Mail::Box::new(body_type)> for a detailed explanation.

=item * deleted =E<gt> BOOL

Is the file deleted from the start?

=item * labels =E<gt> [ STRING =E<gt> VALUE, ... ]

Set the specified labels to their accompanying value.  In most cases, this
value will only be used as boolean, but it might be more complex.

=item * size =E<gt> INTEGER

The size of the message, which includes head and body, but without the
message separators which may be used by the folder type.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBM_deleted}    = $args->{deleted}   || 0;

    $self->{MBM_body_type}  = $args->{body_type}
        if exists $args->{body_type};

    $self->{MBM_labels}   ||= {};
    $self->{MBM_folder}     = $args->{folder};
    weaken $self->{MBM_folder};

    return $self if $self->isDummy;

    $self->{MBM_labels} =
      { seen => 1
      , ($args->{labels} ? @{$args->{labels}} : ())
      };

    $self;
}

#-------------------------------------------

=item folder [FOLDER]

In with folder did we detect this message/dummy?  This is a reference
to the folder-object.

=cut

sub folder(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MBM_folder} = shift;
        weaken($self->{MBM_folder});
    }
    $self->{MBM_folder};
}

#-------------------------------------------

=item delete

Flag the message to be deleted.  The real deletion only takes place on
a synchronization of the folder.

Examples:

   $message->delete;
   delete $message;

=cut

sub delete() { shift->deleted(1) }

#-------------------------------------------

=item deleted [BOOL]

Check or set the deleted flag for this message.  This method returns
undef (not deleted, false) or the time of deletion (true).  With a
BOOL argument, the status is changed first.

Examples:

   if($message->deleted) {...}
   $message->deleted(0);        # undelete

=cut

sub deleted(;$)
{   my $self = shift;
    return $self->{MBM_deleted} unless @_;

    my $delete = shift;
    return $delete if $delete==$self->{MBM_deleted};

    $self->{MBM_deleted} = ($delete ? time : 0);
}

#-------------------------------------------

=item seqnr [INTEGER]

Get (add set) the number of this message is the current folder.

=cut

sub seqnr(;$)
{   my $self = shift;
    @_ ? $self->{MBM_seqnr} = shift : $self->{MBM_seqnr};
}

#-------------------------------------------

=back

=head2 Label management

Labels are used to store knowledge about handling of the message within
the folder.  Flags about whether a message was read, replied to, or
(in some cases) scheduled for deletion.

=over 4

=item setLabel LIST

The LIST is a set of scalars forming key,value pairs.

=cut

sub setLabel(@)
{   my $self   = shift;
    my $labels = $self->labels;
    while(@_)
    {   my $key = shift;          # order of two shifts in one line is not
        $labels->{$key} = shift;  # defined.
    }
    $self->createStatus;
    $self->{MM_modified}++;
    $self;
}

#-------------------------------------------

=item label STRING [ ,STRING ,...]

Get the value related to the label(s).  This returns a list of values, which
may be empty, undefined, or a value which evaluates to TRUE.

Example:

    if($message->label('seen')) {...}
    my ($seen, $current) = $msg->label('seen', 'current');

=cut

sub label(@)
{  my $self = shift;
   wantarray
   ? @{$self->{MBM_labels}}{@_}
   : $self->{MBM_labels}{(shift)};
}

#-------------------------------------------

=item labels

Returns all known labels.  In SCALAR context, it returns the knowledge
as reference to a hash.  This is a reference to the original data, but
you shall *not* change that data directly: call C<setLabel()> for
changes!

In LIST context, you get a list of names which are defined.  Be warned
that they will not all evaluate to true, although most of them will.

=cut

sub labels()
{   my $self = shift;
    wantarray ? keys %{$self->{MBM_labels}} : $self->{MBM_labels};
}

sub statusToLabels($)
{   my ($self, $head) = @_;

    my $labels = $self->{MBM_labels};
    if(my $status = $head->get('status'))
    {   $labels->{seen} = $status =~ /R/;
        $labels->{old}  = $status =~ /O/;
    }
    if(my $xstatus = $head->get('x-status'))
    {   $labels->{replied} = $xstatus =~ /A/;
        $labels->{flagged} = $xstatus =~ /F/;
    }
    $self;
}

sub createStatus()
{   my $self = shift;
    my ($seen, $old, $replied, $flagged)
       = $self->label( qw/seen old replied flagged/ );

    my $head = $self->head;
    $head->set('Status' => ($seen ? 'RO' : $old ? '0' : ''));
    $head->set('X-Status' => ($replied ? 'A' : '').($flagged ? 'F' : ''));

    $self;
}

#-------------------------------------------

=item shortString

Convert the message header to a short string, representing the most
important facts (for debugging purposes only).

=cut

sub shortSize(;$)
{   my $self = shift;
    my $size = shift || $self->head->guessBodySize;

      !defined $size     ? '?'
    : $size < 1_000      ? sprintf "%3d "  , $size
    : $size < 10_000     ? sprintf "%3.1fK", $size/1024
    : $size < 100_000    ? sprintf "%3.0fK", $size/1024
    : $size < 1_000_000  ? sprintf "%3.2fM", $size/(1024*1024)
    : $size < 10_000_000 ? sprintf "%3.1fM", $size/(1024*1024)
    :                      sprintf "%3.0fM", $size/(1024*1024);
}

sub shortString()
{   my $self    = shift;
    my $subject = $self->head->get('subject') || '';
    chomp $subject;

    sprintf "%4s(%2d) %-30.30s", $self->shortSize, $subject;
}

#-------------------------------------------

=item copyTo FOLDER

Copy the message to the indicated opened FOLDER, without deleting the
original.

Example:

   my $draft = $mgr->open(folder => 'Draft');
   $message->copyTo($draft);

=cut

sub copyTo($)
{   my ($self, $folder) = @_;
    $folder->addMessage($self->clone);
    $self;
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

sub head(;$)
{   my $self  = shift;
    return $self->{MM_head} unless @_;  #optimization

    my $old   = $self->{MM_head};
    my $new   = $self->SUPER::head(shift);

    return unless defined $new || defined $old;

    my $folder = $self->{MBM_folder}
        or return $new;

    if(!defined $new && defined $old && !$old->isDelayed)
    {   $folder->messageId($self->messageId, undef);
        $folder->toBeUnthreaded($self);
    }
    elsif(defined $new && !$new->isDelayed)
    {   $folder->messageId($self->messageId, $self);
        $folder->toBeThreaded($self);
    }

    $new || $old;
}

#-------------------------------------------

sub readHead($;$)
{   my $self = shift;
    my $head = $self->SUPER::readHead(@_) or return;
    $self->statusToLabels($head);
    $head;
}

#-------------------------------------------

=item readBody PARSER, HEAD [, BODYTYPE]

Read the body of one message.  The PARSER gives access to the folder file.
The HEAD has been read with C<readHead>.  The optional BODYTYPE supplies
the class name of the body to be created, or a code reference to a
routine which can produce a body type based on the head (passed as
first argument).

By default, the BODYTYPE will call C<determineBodyType> method of the
folder where the message will be added to.

=cut

sub readBody($$;$)
{   my ($self, $parser, $head, $getbodytype) = @_;


    unless($getbodytype)
    {   my $folder   = $self->{MBM_folder};
        $getbodytype = sub {$folder->determineBodyType(@_)};
    }

    $self->SUPER::readBody($parser, $head, $getbodytype);
}

#-------------------------------------------

=item diskDelete

Remove a message from disk.  This is not from the folder, but everything
else, like parts of the message which are stored externally from the
folder.

=cut

sub diskDelete() { shift }

#-------------------------------------------

sub forceLoad() {   # compatibility
   my $self = shift;
   $self->loadBody(@_);
   $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head2 Class structure for messages

As example, the next scheme uses the fake folder-type C<XYZ>, which
may be for instance C<Mbox> or C<MH>.  

    Mail::Box::XYZ::Message
               ^
               |
       Mail::Box::Message
               ^
               |
         Mail::Message
         ::Body ::Head

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_17.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
