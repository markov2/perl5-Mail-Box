
use strict;

package Mail::Message;

use Mail::Box::FastScalar;

=chapter NAME

Mail::Message::Construct::Read - read a Mail::Message from a file handle

=chapter SYNOPSIS

 my $msg1 = Mail::Message->read(\*STDIN);
 my $msg2 = Mail::Message->read(\@lines);

=chapter DESCRIPTION

When complex methods are called on a C<Mail::Message> object, this package
is autoloaded to support the reading of messages directly from any file
handle.

=chapter METHODS

=section Constructing a message

=c_method read $fh|STRING|SCALAR|ARRAY, %options

Read a message from a $fh, STRING, SCALAR, or a reference to an
ARRAY of lines.  Most %options are passed to the M<new()> of the message
which is created, but a few extra are defined.

Please have a look at M<build()> and M<buildFromBody()> before thinking about
this C<read> method.  Use this C<read> only when you have a file-handle
like STDIN to parse from, or some external source of message lines.
When you already have a separate set of head and body lines, then C<read>
is certainly B<not> your best choice.

Some people use this method in a procmail script: the message arrives
at stdin, so we only have a filehandle.  In this case, you are stuck
with this method.  The message is preceded by a line which can be used
as message separator in mbox folders.  See the example how to handle
that one.

This method will remove C<Status> and C<X-Status> fields when they appear
in the source, to avoid the risk that these fields accidentally interfere
with your internal administration, which may have security implications.

=option  strip_status_fields BOOLEAN
=default strip_status_fields <true>

Remove the C<Status> and C<X-Status> fields from the message after
reading, to lower the risk that received messages from external
sources interfere with your internal administration.  If you want
fields not to be stripped (you would like to disable the stripping)
you probably process folders yourself, which is a Bad Thing!

=option  body_type CLASS
=default body_type C<undef>

Force a body type (any specific implementation of a M<Mail::Message::Body>)
to be used to store the message content.  When the body is a multipart or
nested, this will be overruled.

=examples

 my $msg1 = Mail::Message->read(\*STDIN);
 my $msg2 = Mail::Message->read(\@lines, log => 'PROGRESS');
 $folder->addMessages($msg1, $msg2);

 my $msg3 = Mail::Message->read(<<MSG);
 Subject: hello world
 To: you@example.com
                      # warning: empty line required !!!
 Hi, greetings!
 MSG

 # promail example
 my $fromline = <STDIN>;
 my $msg      = Mail::Message->read(\*STDIN);
 my $coerced  = $mboxfolder->addMessage($msg);
 $coerced->fromLine($fromline);
 
=cut

sub read($@)
{   my ($class, $from, %args) = @_;
    my ($filename, $file);
    my $ref       = ref $from;

    if(!$ref)
    {   $filename = 'scalar';
        $file     = Mail::Box::FastScalar->new(\$from);
    }
    elsif($ref eq 'SCALAR')
    {   $filename = 'ref scalar';
        $file     = Mail::Box::FastScalar->new($from);
    }
    elsif($ref eq 'ARRAY')
    {   $filename = 'array of lines';
        my $buffer= join '', @$from;
        $file     = Mail::Box::FastScalar->new(\$buffer);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        local $/;
        my $buffer= <$from>;
        $file     = Mail::Box::FastScalar->new(\$buffer);
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        my $buffer= join '', $from->getlines;
        $file     = Mail::Box::FastScalar->new(\$buffer);
    }
    else
    {   $class->log(ERROR => "Cannot read from $from");
        return undef;
    }

    my $strip_status = exists $args{strip_status_fields}
                     ? delete $args{strip_status_fields}
                     : 1;

    require Mail::Box::Parser::Perl;  # not parseable by C parser

    my $parser = Mail::Box::Parser::Perl->new
     ( %args
     , filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $self = $class->new(%args);
    $self->readFromParser($parser, $args{body_type});
    $self->addReport($parser);

    $parser->stop;

    my $head = $self->head;
    $head->set('Message-ID' => '<'.$self->messageId.'>')
        unless $head->get('Message-ID');

    $head->delete('Status', 'X-Status') if $strip_status;

    $self;
}

1;
