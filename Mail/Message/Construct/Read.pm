
use strict;

package Mail::Message;

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

=c_method read FILEHANDLE|SCALAR|REF-SCALAR|ARRAY-OF-LINES, OPTIONS

Read a message from a FILEHANDLE, SCALAR, a reference to a SCALAR, or
a reference to an array of LINES.  The OPTIONS are passed to the M<new()>
of the message which is created.

Please have a look at M<build()> and M<buildFromBody()> before thinking about
this C<read> method.  Use this C<read> only when you have a file-handle
like STDIN to parse from, or some external source of message lines.
When you already have a separate set of head and body lines, then C<read>
is certainly B<not> your best choice.

Some people use this method in a procmail script: the message arrives
at stdin, so we only have a filehandle.  In this case, you are stuck
with this method.  The message is preceeded by a line which can be used
as message separator in mbox folders.  See the example how to handle
that one.

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
 $coerced->fromLines($fromline);
 
=cut

sub read($@)
{   my ($class, $from) = (shift, shift);
    my ($filename, $file);
    my $ref       = ref $from;

    require IO::Scalar;

    if(!$ref)
    {   $filename = 'scalar';
        $file     = IO::Scalar->new(\$from);
    }
    elsif($ref eq 'SCALAR')
    {   $filename = 'ref scalar';
        $file     = IO::Scalar->new($from);
    }
    elsif($ref eq 'ARRAY')
    {   $filename = 'array of lines';
        my $buffer= join '', @$from;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref eq 'GLOB')
    {   $filename = 'file (GLOB)';
        local $/;
        my $buffer= <$from>;
        $file     = IO::Scalar->new(\$buffer);
    }
    elsif($ref && $from->isa('IO::Handle'))
    {   $filename = 'file ('.ref($from).')';
        my $buffer= join '', $from->getlines;
        $file     = IO::Scalar->new(\$buffer);
    }
    else
    {   croak "Cannot read from $from";
    }

    require Mail::Box::Parser::Perl;  # not parseable by C parser
    my $parser = Mail::Box::Parser::Perl->new
     ( filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $self = $class->new(@_);
    $self->readFromParser($parser);
    $parser->stop;

    my $head = $self->head;
    $head->set('Message-ID' => $self->messageId)
        unless $head->get('Message-ID');

    $self->statusToLabels;
    $self;
}

1;
