
use strict;

package Mail::Box::Message::Destructed;
use base 'Mail::Box::Message';

use Carp;

=chapter NAME

Mail::Box::Message::Destructed - a destructed message

=chapter SYNOPSIS

 $folder->message(3)->destruct;

=chapter DESCRIPTION

When a message folder is read, each message will be parsed into Perl
structures.  Especially the header structure can consume a huge amount
of memory (message bodies can be moved to external temporary files).
Destructed messages have forcefully cleaned-up all header and body
information, and are therefore much smaller.  Some useful information
is still in the object.

BE WARNED: once a message is destructed, it cannot be revived.  Destructing
enforces irreversable deletion from the folder.  If you have a folder opened
for read-only, the message will stay in that folder, but otherwise it may
be deleted.

=chapter METHODS

=c_method new MESSAGE-ID, OPTIONS

You cannot instantiate a destructed message object.  Destruction is
done by calling M<Mail::Box::Message::destruct()>.

=error You cannot instantiate a destructed message
You cannot instantiate a destructed message object directly.  Destruction
is done by calling M<Mail::Box::Message::destruct()> on any existing
folder message.

=cut

sub new(@)
{   my $class = shift;
    $class->log(ERROR => 'You cannot instantiate a destructed message');
    undef;
}
 
#-------------------------------------------

sub isDummy()    { 1 }

#-------------------------------------------

=method head [HEAD]

When C<undef> is specified for HEAD, no change has to take place and
the method returns silently.  In all other cases, this method will
complain that the header has been removed.

=error You cannot take the head/body of a destructed message
The message originated from a folder, but its memory has been freed-up
forcefully by means of M<Mail::Box::Message::destruct()>.  Apparently,
your program still tries to get to the header or body data after this
destruction, which is not possible.

=cut

sub head(;$)
{    my $self = shift;
     return undef if @_ && !defined(shift);

     $self->log(ERROR => "You cannot take the head of a destructed message");
     undef;
}

#-------------------------------------------

=method body [BODY]

When C<undef> is specified for BODY, no change has to take place and
the method returns silently.  In all other cases, this method will
complain that the body data has been removed.

=cut

sub body(;$)
{    my $self = shift;
     return undef if @_ && !defined(shift);

     $self->log(ERROR => "You cannot take the body of a destructed message");
     undef;
}

#-------------------------------------------

=c_method coerce MESSAGE

Coerce a M<Mail::Box::Message> into destruction.

=examples of coercion to death

 Mail::Box::Message::Destructed->coerce($folder->message(1));
 $folder->message(1)->destruct;  # same

 my $msg = $folder->message(1);
 Mail::Box::Message::Destructed->coerce($msg);
 $msg->destruct;                 # same

=error Cannot coerce a (class) into destruction
Only real M<Mail::Box::Message> objects can get destructed into
M<Mail::Box::Message::Destructed> objects.  M<Mail::Message> free
their memory immediately when the last reference is lost.

=cut

sub coerce($)
{  my ($class, $message) = @_;

   unless($message->isa('Mail::Box::Message'))
   {  $class->log(ERROR=>"Cannot coerce a ",ref($message), " into destruction");
      return ();
   }

   $message->delete;
   $message->body(undef);
   $message->head(undef);

   bless $message, $class;
}

#-------------------------------------------

=method deleted [BOOLEAN]

It is possible to delete a destructed message, but not to undelete it.

=error Destructed messages can not be undeleted
Once a message is destructed, it can not be revived.  Destruction is an
optimization in memory usage: if you need an undelete functionality, then
you can not use M<Mail::Box::Message::destruct()>.

=cut

sub deleted(;$)
{  my $self = shift;

   $self->log(ERROR => "Destructed messages can not be undeleted")
      if @_ && not $_[0];

   $self->delete;
}

1;
