use strict;
use warnings;

package Mail::Box::Parser;
use base 'Mail::Reporter';
use Carp;

=chapter NAME

Mail::Box::Parser - reading and writing messages

=chapter SYNOPSIS

 # Not instatiatiated itself

=chapter DESCRIPTION

The C<Mail::Box::Parser> manages the parsing of folders.  Usually, you won't
need to know anything about this module, except the options which are
involved with this code.

There are two implementations of this module planned:

=over 4

=item * M<Mail::Box::Parser::Perl>
A slower parser which only uses plain Perl.  This module is a bit slower,
and does less checking and less recovery.

=item * M<Mail::Box::Parser::C>
A fast parser written in C<C>.  This package is released as separate
module on CPAN, because the module distribution via CPAN can not
handle XS files which are not located in the root directory of the
module tree.  If a C compiler is available on your system, it will be
used automatically.

=back

=chapter METHODS

=c_method new %options

Create a parser object which can handle one file.  For
mbox-like mailboxes, this object can be used to read a whole folder.  In
case of MH-like mailboxes, each message is contained in a single file,
so each message has its own parser object.

=requires  filename FILENAME
The name of the file to be read.

=option  file FILE-HANDLE
=default file undef
Any C<IO::File> or C<GLOB> which can be used to read the data from.  In
case this option is specified, the C<filename> is informational only.

=option  mode OPENMODE
=default mode C<'r'>
File-open mode, which defaults to C<'r'>, which means `read-only'.
See C<perldoc -f open> for possible modes.  Only applicable 
when no C<file> is specified.

=error Filename or handle required to create a parser.
A message parser needs to know the source of the message at creation.  These
sources can be a filename (string), file handle object or GLOB.
See new(filename) and new(file).

=cut

sub new(@)
{   my $class = shift;

    $class eq __PACKAGE__
    ? $class->defaultParserType->new(@_)   # bootstrap right parser
    : $class->SUPER::new(@_);
}

sub init(@)
{   my ($self, $args) = @_;

#warn "PARSER type=".ref $self,$self->VERSION;
    $self->SUPER::init($args);

    $self->{MBP_mode} = $args->{mode} || 'r';

    unless($self->{MBP_filename} = $args->{filename} || ref $args->{file})
    {    $self->log(ERROR => "Filename or handle required to create a parser.");
         return;
    }

    $self->start(file => $args->{file});
}

#------------------------------------------

=section The parser

=method start %options
Start the parser by opening a file.

=option  file FILEHANDLE|undef
=default file undef
The file is already open, for instance because the data must be read
from STDIN.
=cut

sub start(@)
{   my $self = shift;
    my %args = (@_, filename => $self->filename, mode => $self->{MBP_mode});

    $self->openFile(\%args)
        or return;

    $self->takeFileInfo;

    $self->log(PROGRESS => "Opened folder $args{filename} to be parsed");
    $self;
}

#------------------------------------------

=method stop
Stop the parser, which will include a close of the file.  The lock on the
folder will not be removed (is not the responsibility of the parser).

=warning File $filename changed during access.
When a message parser starts working, it takes size and modification time
of the file at hand.  If the folder is written, it checks wether there
were changes in the file made by external programs.

Calling M<Mail::Box::update()> on a folder before it being closed
will read these new messages.  But the real source of this problem is
locking: some external program (for instance the mail transfer agent,
like sendmail) uses a different locking mechanism as you do and therefore
violates your rights.

=cut

sub stop()
{   my $self     = shift;

    my $filename = $self->filename;

#   $self->log(WARNING => "File $filename changed during access.")
#      if $self->fileChanged;

    $self->log(NOTICE  => "Close parser for file $filename");
    $self->closeFile;
}

=method restart
Restart the parser on a certain file, usually because the content has
changed.
=cut

sub restart()
{   my $self     = shift;
    my $filename = $self->filename;

    $self->closeFile;
    $self->openFile( {filename => $filename, mode => $self->{MBP_mode}} )
        or return;

    $self->takeFileInfo;
    $self->log(NOTICE  => "Restarted parser for file $filename");
    $self;
}

=method fileChanged
Returns whether the file which is parsed has changed after the last
time takeFileInfo() was called.
=cut

sub fileChanged()
{   my $self = shift;
    my ($size, $mtime) = (stat $self->filename)[7,9];
    return 0 if !defined $size || !defined $mtime;
    $size != $self->{MBP_size} || $mtime != $self->{MBP_mtime};
}
    
=method filename
Returns the name of the file this parser is working on.
=cut

sub filename() {shift->{MBP_filename}}

#------------------------------------------

=section Parsing

=method filePosition [$position]

Returns the location of the next byte to be used in the file which is
parsed.  When a $position is specified, the location in the file is
moved to the indicated spot first.

=cut

sub filePosition(;$) {shift->NotImplemented}

=method pushSeparator STRING|Regexp
Add a boundary line.  Separators tell the parser where to stop reading.
A famous separator is the C<From>-line, which is used in Mbox-like
folders to separate messages.  But also parts (I<attachments>) is a
message are divided by separators.

The specified STRING describes the start of the separator-line.  The
Regexp can specify a more complicated format.
=cut

sub pushSeparator($) {shift->notImplemented}

=method popSeparator
Remove the last-pushed separator from the list which is maintained by the
parser.  This will return C<undef> when there is none left.
=cut

sub popSeparator($) {shift->notImplemented}

=method readSeparator %options
Read the currently active separator (the last one which was pushed).  The
line (or C<undef>) is returned.  Blank-lines before the separator lines
are ignored.

The return are two scalars, where the first gives the location of the
separator in the file, and the second the line which is found as
separator.  A new separator is activated using M<pushSeparator()>.
=cut

sub readSeparator($) {shift->notImplemented}

=method readHeader
Read the whole message-header and return it as list of field-value
pairs.  Mind that some fields will appear more than once.

The first element will represent the position in the file where the
header starts.  The follows the list of header field names and bodies.

=example
 my ($where, @header) = $parser->readHeader;

=cut

sub readHeader()    {shift->notImplemented}

=method bodyAsString [$chars, [$lines]]
Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or $lines to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of three scalars, the location in the file
where the body starts, where the body ends, and the string containing the
whole body.
=cut

sub bodyAsString() {shift->notImplemented}

=method bodyAsList [$chars, [$lines]]
Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or $lines to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of scalars, each containing one line (including
line terminator), preceded by two integers representing the location
in the file where this body started and ended.
=cut

sub bodyAsList() {shift->notImplemented}

=method bodyAsFile $fh [$chars, [$lines]]
Try to read one message-body from the file, and immediately write
it to the specified file-handle.  Optionally, the predicted number
of CHARacterS and/or $lines to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of three scalars: the location of the body (begin
and end) and the number of lines in the body.
=cut

sub bodyAsFile() {shift->notImplemented}

=method bodyDelayed [$chars, [$lines]]
Try to read one message-body from the file, but the data is skipped.
Optionally, the predicted number of CHARacterS and/or $lines to be skipped
can be supplied.  These values may be C<undef> and may be wrong.

The return is a list of four scalars: the location of the body (begin and
end), the size of the body, and the number of lines in the body.  The
number of lines may be C<undef>.
=cut

sub bodyDelayed() {shift->notImplemented}

=method lineSeparator
Returns the character or characters which are used to separate lines
in the folder file.  This is based on the first line of the file.
UNIX systems use a single LF to separate lines.  Windows uses a CR and
a LF.  Mac uses CR.
=cut

sub lineSeparator() {shift->{MBP_linesep}}

#------------------------------------------

=section Internals

=method openFile $args
Open the file to be parsed.  $args is a ref-hash of options.

=requires filename FILENAME
=requires mode STRING
=cut

sub openFile(@) {shift->notImplemented}

=method closeFile
Close the file which was being parsed.
=cut

sub closeFile(@) {shift->notImplemented}

=method takeFileInfo
Capture some data about the file being parsed, to be compared later.
=cut

sub takeFileInfo()
{   my $self     = shift;
    @$self{ qw/MBP_size MBP_mtime/ } = (stat $self->filename)[7,9];
}

=ci_method defaultParserType [$class]
Returns the parser to be used to parse all subsequent
messages, possibly first setting the parser using the optional argument.
Usually, the parser is autodetected; the C<C>-based parser will be used
when it can be, and the Perl-based parser will be used otherwise.

The $class argument allows you to specify a package name to force a
particular parser to be used (such as your own custom parser). You have
to C<use> or C<require> the package yourself before calling this method
with an argument. The parser must be a sub-class of C<Mail::Box::Parser>.
=cut

my $parser_type;

sub defaultParserType(;$)
{   my $class = shift;

    # Select the parser manually?
    if(@_)
    {   $parser_type = shift;
        return $parser_type if $parser_type->isa( __PACKAGE__ );

        confess "Parser $parser_type does not extend "
              . __PACKAGE__ . "\n";
    }

    # Already determined which parser we want?
    return $parser_type if $parser_type;

    # Try to use C-based parser.
    eval 'require Mail::Box::Parser::C';
#warn "C-PARSER errors $@\n" if $@;

    return $parser_type = 'Mail::Box::Parser::C'
        unless $@;

    # Fall-back on Perl-based parser.
    require Mail::Box::Parser::Perl;
    $parser_type = 'Mail::Box::Parser::Perl';
}

#------------------------------------------

=section Error handling

=section Cleanup

=cut

sub DESTROY
{   my $self = shift;
    $self->stop;
    $self->SUPER::DESTROY;
}

1;
