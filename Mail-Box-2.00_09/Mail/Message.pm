use strict;
use warnings;

package Mail::Message;
use base 'Mail::Reporter';

use Mail::Message::Part;
use Mail::Message::CoDec;

use Carp;

our $VERSION = '2.00_09';

=head1 NAME

Mail::Message - basic message object

=head1 CLASS HIERARCHY

 Mail::Message
 is a Mail::Reporter

=head1 SYNOPSIS

  use Mail::Box::Manager;
  my $mgr    = Mail::Box::Manager->new;
  my $folder = $mgr->open(folder => $MAIL);
  my $msg    = $folder->message(2);    # $msg isa Mail::Message

  $msg->decoded->print($outfile);

  my Mail::Message $construct  = Mail::Message->new;
  my Mail::Message::Head $head = $msg->head;
  my Mail::Message::Body $body = $msg->body;

=head1 DESCRIPTION

A C<Mail::Message> object is a container for message information read from a
file.  Everything what is not folder related will be found here.

Complex message handling (like construction of replies) are handled by the
C<Mail::Message::Construct> package which is autoloaded.  That package
adds functionality to the C<Mail::Message> objects.

The main methods are C<get()> -to get information from a message
header- and C<decoded()> to get the intented content of a message.

=head1 METHOD INDEX

The general methods for C<Mail::Message> objects:

      attach MESSAGES [,OPTIONS]           modified [BOOL]
      decoded OPTIONS                      new OPTIONS
      encode TYPE                          nrLines
   MR errors                               parent
      get FIELD                            print [FILEHANDLE]
      guessTimestamp                    MR report [LEVEL]
      isDelayed                         MR reportAll [LEVEL]
      isDummy                              size
      isMultipart                          timestamp
      isPart                               toplevel
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      messageId                         MR warnings

The extra methods for extension writers:

      body [BODY]                       MR logPriority LEVEL
      clone                             MR logSettings
      coerce MESSAGE [,OPTIONS]         MR notImplemented
      head [OBJECT]                        read PARSER, HEADTYPE, BODY...

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new OPTIONS

Create a new message object.  The message's head and body will
be read later, unless specified at construction.

 OPTION            DESCRIBED IN       DEFAULT
 body              Mail::Message      undef
 head              Mail::Message      undef
 log               Mail::Reporter     'WARNINGS'
 messageId         Mail::Message      undef
 modified          Mail::Message      0
 trace             Mail::Reporter     'WARNINGS'

=over 4

=item * body =E<gt> OBJECT

Instantiate the message with a body which has been created somewhere
before the message is constructed.  The OBJECT must be a sub-class
of C<Mail::Message::Body>.

=item * head =E<gt> OBJECT

Instantiate the message with a head which has been created somewhere
before the message is constructed.  The OBJECT must be a (sub-)class
of C<Mail::Message::Head>.

=item * messageId =E<gt> STRING

The id on which this message can be recognized.  If none specified and
not defined in the header --but one is needed-- there will be one assigned
to the message to be able to pass unique message-ids between objects.

=item * modified =E<gt> BOOL

Flags this message as being modified, from the beginning on.  Usually,
modification is auto-detected, but there may be reasons to be extra
explicit.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MM_modified} = $args->{modified} || 0;

    # Set the header

    my $head;
    if($head = $args->{head})
    {   $self->{MM_head} = $head;
        $head->message($self);
    }

    if(my $msgid = $args->{messageId} || $args->{messageID})
                 { $self->takeMessageId($msgid) }
    elsif($head) { $self->takeMessageId($head->get('message-id')) }

    # Set the body
    if(my $body = $args->{body})
    {   $self->{MM_body} = $body;
        $body->message($self);
    }

    $self;
}

#------------------------------------------

=item get FIELD

Returns the value which is stored in the header FIELD with the specified
name.  If no header is known yet, or the field is not defined, then
C<undef> is returned.  If the field has multiple appearances in the
header, the last instance is returned.

The field name is case insensitive.  Only the `body' of the field is
returned, not the comment (after ';').  If you need more complex handing
of fields, then call

Example:

 print $msg->get('Content-Type'), "\n";

Is equivalent to:

 print $msg->head->get('Content-Type')->body, "\n";

=cut

sub get($)
{   my $head  = shift->head || return;
    my $field = $head->get(shift) || return;
    $field->body;
}

#------------------------------------------

=item decoded OPTIONS

Decodes the body of this message, and returns it as a body object.  If there
was no encoding, the body object as read from file is passed on, however,
some more work will be needed when a serious encoding is encountered.
The OPTIONS control how the conversion takes place.

 OPTION            DESCRIBED IN          DEFAULT
 codec             Mail::Message         undef
 keep              Mail::Message         0
 result            Mail::Message         undef

=over 4

=item * codec =E<gt> CODEC

The specified CODEC object must be used to decode this message's body.

=item * keep =E<gt> BOOL

Controls whether the decoded result will be kept.  If not, the decoding
may be performed more than once.  However, it will consume extra
resources...

=item * result =E<gt> BODY

Specify any body which will be used to return the result.  By default,
a convient body will be created: binary data will be temporily stored
in external files and text data as lines.

=back

Example:

   $message->decoded->print(\*STDOUT);
   $message->body($message->decoded);

=cut

sub decoded(@)
{   my ($self, %args) = @_;

    return $self->{MB_decoded} if $self->{MB_decoded};

    my $body   = $self->body or return;

    if($body->isMultipart)
    {   return ref($body)->new
          ( preamble => $body->preamble
          , parts    => [ map {$_->decoded} $body->parts ]
          , epilogue => $body->epilogue
          );
    }
  
    # Find decoder

    my $codec  = $args{codec};
    unless($codec)
    {   my $encoding = $self->get('Content-Transfer-Encoding')
            or return $body;

        $codec = Mail::Message::CoDec->create($encoding, $self->logSettings);

        unless($codec)
        {   $self->log(WARNING => "No decoder for $encoding");
            return $body;
        }
    }

    # Determine result object

    my $result   = $args{result};
    unless($result)
    {   my $mimetype = $self->head->get('Content-Type');
        $mimetype    = $mimetype->body if $mimetype;

        my $resulttype = defined $mimetype && $mimetype =~ m!text/!
           ? 'Mail::Message::Body::Lines' : 'Mail::Message::Body::File';

        $result      = $resulttype->new($body->logSettings);
    }

    my $decoded = $codec->decode($body, $result);
    $self->{MB_decoded} = $decoded if $args{keep};
    $decoded;
}

#------------------------------------------

=item encode TYPE, OPTIONS

Set the encoding of the message's body to the specified type.  For multipart
messages, each of the attachments get encoded.  De body of the message is
replaced by the encoded version.  If the body already is encoded in the
right way, nothing will be done.  When the body is encoded in the wrong
a different type than requested, decoding will be done first.
The newly encoded body is returned.

 OPTION            DESCRIBED IN          DEFAULT
 codec             Mail::Message         undef
 replace           Mail::Message         1
 result            Mail::Message         undef

=over 4

=item * codec =E<gt> CODEC

The specified CODEC object must be used to encode this message's body.  In
case you specify a codec, the TYPE parameter will be ignored.

=item * replace =E<gt> BOOL

If true (default), the encoded body replaces the original body in the
message.

=item * result =E<gt> BODY

The encoded data will be stored in the specified BODY if real work is
done.  Otherwise, the data will stay in the original body.  With this
option, you have a way to control which kind of body is created, if
one is created...

=back

Example:

 $msg->encode('Base64');

=cut

sub encode($)
{   my ($self, $type, %args) = @_;
    my $orig = $self->{MM_body};
    my @log  = $self->logSettings;

    if($self->isMultipart)
    {   return ref($orig)->new
          ( preamble => $orig->preamble
          , parts    => [ map {$_->encode($type, %args)} $orig->parts ]
          , epilogue => $orig->epilogue
          , @log
          );
    }

    my $codec  = $args{codec};
    if($codec) { $type = $codec->name }
    elsif($type)
    {   $codec = Mail::Message::CoDec->create($type, @log);
        unless($codec)
        {   $self->log(WARNING => "No encoder for $type");
            return $orig;
        }
    }

    my $encoding = $self->get('Content-Transfer-Encoding');
    return $orig if $encoding && $type && $encoding eq $type;

    my $result  = $args{result} || ref($orig)->new(@log);
    my $decoded = $encoding ? $self->decoded : $orig;
    my $encoded = $codec ? $codec->encode($decoded, $result) : $decoded;

    $self->body($encoded, transfer_encoding => $type)
       if !defined $args{replace} || $args{replace};
    
    $encoded;
}

#-------------------------------------------

=item modified [BOOL]

Returns (optionally after setting) whether this message is flagged as
being modified.  The modification flag is set C<true> when header lines
are changed, the header or body replaced by a new one, or when labels
are modified.

=cut

sub modified(;$)
{   my $self = shift;

    if(@_)
    {   my $flag = shift;
        $self->{MM_modified} = $flag;
        my $head = $self->head;
        $head->modified($flag) if $head;
        my $body = $self->body;
        $body->modified($flag) if $body;
    }

    return 1 if $self->{MM_modified};

    my $head = $self->head;
    if($head && $head->modified)
    {   $self->{MM_modified}++;
        return 1;
    }

    my $body = $self->body;
    if($body && $body->modified)
    {   $self->{MM_modified}++;
        return 1;
    }

    0;
}

#------------------------------------------

=item parent

=item isPart

=item toplevel

If the message is a part of another message, C<parent> returns the reference
to the containing message. C<parent> returns C<undef> if the message is not a
part, but rather the main message.  C<isPart> returns true if the message
is a part of another message.  C<toplevel> returns a reference to the main
message, which will be the current message if the message is not part of
another message.

Examples:

    my Mail::Message $msg = ...

    return unless $msg->body->isMultipart;
    my $part   = $msg->body->part(2);

    return unless $part->body->isMultipart;
    my $nested = $part->body->part(3);

    $nested->parent;     # returns $part
    $nested->toplevel;   # returns $msg
    $msg->parent;        # returns undef
    $msg->toplevel;      # returns $msg
    $msg->isPart;        # returns false
    $part->isPart;       # returns true

=cut

sub parent()     { undef }   # overridden by Mail::Message::Part
sub toplevel()   { shift }   # idem
sub isPart()     { 0 }       # idem

#-------------------------------------------

=item messageId

Retrieve the message's id.  Every message has a unique message-id.  This id
is used mainly for recognizing discussion threads.

=cut

sub messageId() {shift->{MM_message_id}}
sub messageID() {shift->messageId}   # compatibility

#-------------------------------------------

=item guessTimestamp

Return an estimate on the time this message was sent.  The data is
derived from the header, where it can be derived from the C<date> and
C<received> lines.  For MBox-like folders you may get the date from
the from-line as well.

This method may return C<undef> if the header is not parsed or only
partially known.  If you require a time, then use the C<timestamp()>
method, described below.

Examples:

    print "Receipt ", ($message->timestamp || 'unknown'), "\n";

=cut

sub guessTimestamp() {shift->head->guessTimestamp}

#-------------------------------------------

=item timestamp

Get a timestamp, doesn't matter how much work it is.  If it is impossible
to get a time from the header-lines, the current time-of-living is taken.

=cut

sub timestamp() {shift->head->timestamp}

#-------------------------------------------

=item isDelayed

C<isDelayed> checks whether the message is delayed (not yet read from file).
Returns true or false.  For this, it checks the body-type.

=cut

sub isDelayed() {shift->body->isDelayed}

#------------------------------------------

=item isDummy

Dummy messages are used to fill holes in linked-list and such, where only
a message-id is known, but not the place of the header of body data.

This method is also available for C<Mail::Message::Dummy> objects, where
this will return C<true>.  On any extention of C<Mail::Message>, this will
return C<false>.

=cut

sub isDummy()    { 0 }

#------------------------------------------

=item isMultipart

Check whether this message is a multipart message (has attachments).  To
find this out, we need at least the header of the message; there is no
need to read the body of the message to detect this.

=cut

sub isMultipart() {shift->body->isMultipart}

#------------------------------------------

=item attach MESSAGES [,OPTIONS]

Attach one or more MESSAGES to this one.  For multipart messages, this is
a simple task, but other types of message-bodies will have to be
converted into a multipart first.

=cut

sub attach(@)
{   my $self = shift;

    my @messages;
    push @messages,  shift
        while @_ && ref $_[0] && $_[0]->isa('Mail::Message');

    require Mail::Message::Construct;
    my $multi = $self->body2multipart(@_);
    $multi->addPart($_) foreach @messages;

    $self->body($multi);
    $self;
}

#------------------------------------------
# All next routines try to create compatibility with release < 2.0

sub isParsed()   { not shift->isDelayed }
sub headIsRead() { not shift->head->isa('Mail::Message::Delayed') }

#-------------------------------------------
# Next routines try to create compatibility with Mail::Internet and
# MIME::Entity

sub bodyhandle()
{   my $self = shift;
    $self->isMultipart ? undef : $self->body->decoded;
}

sub parts(;$)   # optional index
{   my $self = shift;

      ! $self->isMultipart ? ()
    : ! @_                 ? $self->body->parts
    :                        $self->body->part(shift);
}

#------------------------------------------

=item print [FILEHANDLE]

Print the message to the FILE-HANDLE, which defaults to STDOUT.

Examples:

 $message->print(\*STDERR);
 $message->print;

 my $out = IO::File->new('out', 'w');
 $message->print($out);

=cut

sub print(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    $self->head->print($out);
    $self->body->print($out);
    $self;
}

#------------------------------------------

=item size

Returns the size of the whole message in bytes.

=cut

sub size()
{   my $self = shift;
    $self->head->size + $self->body->size;
}

#------------------------------------------

=item nrLines

Returns the number of lines used for the whole message.

=cut

sub nrLines()
{   my $self = shift;
    $self->head->nrLines + $self->body->nrLines;
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

=item clone

Create a copy of this message.  The head and body, the log
and trace levels are taken.  The logged reports are not taken.
The copy will not be added to any folder automatically.
 
BE WARNED: if you intend to change the content of the message, you
will have to change the message-id in the reader also.

Example:

   $copy = $msg->clone;

See also the C<copyTo FOLDER>, C<moveTo FOLDER>, and C<reply> methods.

=cut

sub clone()
{   my $self  = shift;
    my $class = ref $self;

    $class->new
     ( head  => $self->head->clone
     , body  => $self->body->clone
     , $self->logSettings
     );
}

#------------------------------------------

=item read PARSER, HEADTYPE, BODYTYPE, WRAP

Read one message from file.  The PARSER reads the file.  HEADTYPE is the
class of the header to be created. BODYTYPE is the class of the body object
to be created.  The WRAP flags the desired maximum length of structured
header fields.

BODYTYPE is a code reference to routine which returns a string.  The string
is the name of a class which extends C<Mail::Message::Body>.  The code will
be called with the created header object and a size estimated (possibly
C<undef>).  The optons third argument flags whether a delayed load is
acceptable or not.

=cut

sub read($$$$)
{   my ($self, $parser, $headtype, $getbodytype, $wrap) = @_;

    my @log      = $self->logSettings;
    my $head     = $headtype->new(@log, wrap_length => $wrap)->read($parser)
        or return;

    $self->{MM_head} = $head;
    $head->message($self);
    $self->takeMessageId($head->get('message-id'));

#warn "head was read\n";
    my $lines    = $head->get('Lines');
    my $size     = $head->guessBodySize;
    my $bodytype = $getbodytype->($head, $size, 1);

#warn "bodytype will be $bodytype";
    my $body     = $bodytype->new(@log)
                            ->read($parser, $head, $getbodytype, $size, $lines)
        or return;
#warn "body was read\n";

    $self->{MM_body} = $body;
    $body->message($self);

    $self;
}

#------------------------------------------

=item body [BODY, OPTIONS]

Return the body of this message.  Be warned that this returns
you an object which still may be encoded: use C<decoded> to get the
usable data.

With options, a new BODY is set for this message.  The body must
be an (sub-)class of C<Mail::Message::Body>.  In this case, you may
want to update the related header fields too.

 OPTION             DESCRIBED IN       DEFAULT
 content_type       Mail::Message      text/plain
 content_length     Mail::Message      <actual size>
 transfer_encoding  Mail::Message      undef
 lines              Mail::Message      <actual lines>

If the C<content_encoding> is specified, then the body is considered
being encoded.  If not, it depends on C<content_type> of the body
whether encoding will take place.

Examples:

 my @encoded = $msg->body->lines;
 print STDERR $msg->body;       # same
 $msg->body(Mail::Message::Body::Lines->new, content_type => 'text/html');

=cut
  
sub body(;$)
{   my $self = shift;
    return $self->{MM_body} unless @_;

    my ($body, %args) = @_;
    confess "Internal error: wrong type of body for $body"
        unless ref $body && $body->isa('Mail::Message::Body');

    $body->message($self);
    $self->{MM_modified}++ if $self->{MM_body};

    my $type = $args{content_type} || 'text/plain';
    my $head = $self->head;
    $head->set('Content-Type'   => $type);
    $head->set('Content-Length' => $args{content_length} || $body->size);

    my $lines = defined $args{lines} ? $args{lines} : $body->nrLines;
    $head->set('Lines' => $lines) if $lines;

    delete $self->{MM_decoded};
    $self->{MM_body} = $body;

    if(exists $args{transfer_encoding})
    {   my $encoding = $args{transfer_encoding};
        if(defined $encoding)
             { $head->set('Content-Transer-Encoding' => $encoding) }
        else { $head->reset('Content-Transer-Encoding') }
        return $body;
    }

    my $encoding = $type =~ m!^text/! ? undef : 'Base64';
    $self->encode($encoding, replace => 1);
}

#------------------------------------------

=item head [HEAD]

Return (optionally after setting) the HEAD of this message.
The head must be an (sub-)class of C<Mail::Message::Head>.

Example:

    my $head = $msg->head(new Mail::Message::Head);

=cut

sub head(;$)
{   my $self   = shift;
    return $self->{MM_head} unless @_;

    my $head = shift;
    die "Internal error: wrong type of head for $_[0]"
        unless ref $head && $head->isa('Mail::Message::Head');

    $head->message($self);

    $self->{MM_modified}++ if $self->{MM_head};

    $self->{MM_head} = $head;
    $self->takeMessageId($head->get('message-id'));

    $head;
}

#------------------------------------------

=item takeMessageId [STRING]

Take the message-id from the string, or create one when the C<undef>
is specified.  Angles (if present) are removed from the id.

=cut

sub takeMessageId($)
{   my ($self, $msgid) = @_;

    return $self->{MM_message_id} = $self->head->createMessageId
        unless defined $msgid;
    
    if($msgid =~ m/\<([^>]*)\>/s)
    {   $msgid = $1;
        $msgid =~ s/\s//gs;
    }

    $self->{MM_message_id} = $msgid;
}

#------------------------------------------

=item coerce MESSAGE [,OPTIONS]

(Class method) Coerce a MESSAGE into a C<Mail::Message>.  In some
occations, for instance where you add a message to a folder, this
coercion is automatically called to ensure that the correct message
type is stored.

The coerced message is returned on success, otherwise C<undef>.  The
coerced message may be a reblessed version of the original message
or a new object.

Example:

   my $message = Mail::Message->new(...);
   my $coerced = Mail::Box::MBox::Message->coerce($message);
   # now $coerced is a Mail::Box::Mbox::Message

It is better to use (when the message will be stored in that folder):

   my $folder  = Mail::Box::Mbox->new;
   my $coerced = $folder->coerce($message);
   my $coerced = $folder->addMessage($message);

=cut

my $mail_internet_converter;
my $mime_entity_converter;

sub coerce($)
{   my ($class, $message) = @_;

confess "@_" unless $message;
    return bless $message, $class
        if $message->isa(__PACKAGE__);

    if($message->isa('MIME::Entity'))
    {   unless($mime_entity_converter)
        {   eval {require Mail::Message::Convert::MimeEntity};
                confess "Install MIME::Entity" if $@;

            $mime_entity_converter = Mail::Message::Convert::MailInternet->new;
        }

        $message = $mime_entity_converter->from($message)
            or return;
    }

    elsif($message->isa('Mail::Internet'))
    {   unless($mail_internet_converter)
        {   eval {require Mail::Message::Convert::MailInternet};
            confess "Install Mail::Internet" if $@;

            $mail_internet_converter = Mail::Message::Convert::MimeEntity->new;
        }

        $message = $mail_internet_converter->from($message)
            or return;
    }

    else
    {   confess "Cannot coerce ".ref($message)." objects into "
              . __PACKAGE__." objects.\n";
    }

    bless $message, $class;
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_09.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
