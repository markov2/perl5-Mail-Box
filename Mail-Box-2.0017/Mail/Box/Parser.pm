use strict;
use warnings;

package Mail::Box::Parser;
use base 'Mail::Reporter';
use Carp;

our $VERSION = 2.00_17;

=head1 NAME

Mail::Box::Parser - Reading and writing messages

=head1 CLASS HIERARCHY

 Mail::Box::Parser
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

The C<Mail::Box::Parser> manages the parsing of folders.  Usually, you won't
need to know anything about this module, except the options which are
involved with this code.

There are two implementations of this module included in this
distribution:

=over 4

=item * C<Mail::Box::Parser::C>

A fast parser written in C<C>, using C<Inline::C>.  If it is possible to
install C<Inline::C> on your system, this module will automatically
compiled during installation.  It will be much faster than the other
option.

=item * C<Mail::Box::Parser::Perl>

A slower parser which only uses plain Perl.  This module is a bit slower,
and does less checking and less recovery.

=back

Each implementation supplies the same methods, as described below.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Parser> objects:

      bodyAsFile FILEHANDLE [,CHA...       new [OPTIONS]
      bodyAsList [,CHARS [,LINES]]         popSeparator
      bodyAsString [,CHARS [,LINES]]       pushSeparator STRING
      bodyDelayed [,CHARS [,LINES]]        readHeader WRAP
      defaultParserType [CLASS]            readSeparator OPTIONS
   MR errors                            MR report [LEVEL]
      filePosition [POSITION]           MR reportAll [LEVEL]
      foldHeaderLine LINE, LENGTH          start OPTIONS
      inDosmode                            stop
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#------------------------------------------

=item new [OPTIONS]

(Class method)  Create a parser object which can handle one file.  For
mbox-like mailboxes, this object can be used to read a whole folder.  In
case of MH-like mailboxes, each message is contained in a single file,
so each message has its own parser object.

The OPTIONS can be

 OPTIONS           DESCRIBED IN          DEFAULT
 filename          Mail::Box::Parser     <required>
 log               Mail::Reporter        'WARNINGS'
 mode              Mail::Box::Parser     'r'
 trace             Mail::Reporter        'WARNINGS'

The options specific to C<Mail::Box::Parser> are:

=over 4

=item * filename =E<gt> FILENAME

(Required) The name of the file to be read.

=item * mode =E<gt> OPENMODE

File-open mode, which defaults to C<'r'>, which means `read-only'.
See C<perldoc -f open> for possible modes.

=back

=cut

sub new(@)
{   my $class       = shift;

    return $class->defaultParserType->new(@_)   # bootstrap right parser
        if $class eq __PACKAGE__;

    my $self = $class->SUPER::new(@_) or return;
    $self->start;     # new includes init.
}

sub init(@)
{   my ($self, $args) = @_;

    $args->{trace} ||= 'WARNING';

    $self->SUPER::init($args);

    $self->{MBP_separator} = $args->{separator} || '';
    $self->{MBP_mode}      = $args->{mode}      || 'r';

    my $filename =
    $self->{MBP_filename}  = $args->{filename}
        or confess "Filename obligatory to create a parser.";

    @$self{ qw/MBP_size MBP_mtime/ }
                           = (stat $filename)[7,9];

    $self->log(NOTICE => "Created parser for $filename");

    $self;
}

#------------------------------------------

=item defaultParserType [CLASS]

(Class or instance method) Returns the parser to be used to parse all subsequent
messages, possibly first setting the parser using the optional argument.
Usually, the parser is autodetected; the C<C>-based parser will be used
when it can be, and the C<Perl>-based parser will be used otherwise.

The CLASS argument allows you to specify a package name to force a
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
#   return $parser_type = 'Mail::Box::Parser::C'
#       unless $@;

    # Fall-back on Perl-based parser.
    require Mail::Box::Parser::Perl;
    $parser_type = 'Mail::Box::Parser::Perl';
}

#------------------------------------------

=item start OPTIONS

Start the parser.  The parser is automatically started when the parser is
created, however can be stopped (see C<stop()> below).  During the start,
the file to be parsed will be opened.

Start has the following OPTIONS:

=over 4

=item * trust_file =E<gt> BOOLEAN

When we continue with the parsing of the folder, and the modification-time
(on operating-systems which support that) or size changed, the parser
will refuse to start, unless this option is true.

=back

=cut

sub start(@)
{   my ($self, %args) = @_;

    my $filename = $self->{MBP_filename};

    unless($args{trust_file})
    {   my ($size, $mtime) = (stat $filename)[7,9];

        unless(   (defined $mtime && $self->{MBP_mtime} == $mtime)
               && $self->{MBP_size} == $size)
        {   $self->log(ERROR => "File $filename changed, refuse to continue.");
            return;
        }
    }

    $self->log(NOTICE => "Open file $filename to be parsed");
    $self;
}

#------------------------------------------

=item stop

Stop the parser, which will include a close of the file.  The lock on the
folder will not be removed.

=cut

sub stop()
{   my $self = shift;

    my $filename       = $self->{MBP_filename};
    my ($size, $mtime) = (stat $filename)[7,9];

    $self->log(ERROR => "File $filename changed during access.")
       if  defined $mtime && $self->{MBP_mtime} != $mtime
        || $self->{MBP_size} != $size;

    $self->log(NOTICE => "Close parser for file $filename");
    $self;
}

#------------------------------------------

=item filePosition [POSITION]

Returns the location of the next byte to be used in the file which is
parsed.  When a POSITION is specified, the location in the file is
moved to the indicated spot first.

=cut

sub filePosition(;$) {shift->NotImplemented}

#------------------------------------------

=item pushSeparator STRING|REGEXP

Add a boundary line.  Separators tell the parser where to stop reading.
A famous seperator is the C<From>-line, which is used in Mbox-like
folders to separate messages.  But also parts (I<attachments>) is a
message are devided by separators.

The specified STRING describes the start of the separator-line.  The
REGEXP can specify a more complicated format.

=cut

sub pushSeparator($) {shift->notImplemented}

#------------------------------------------

=item popSeparator

Remove the last-pushed separator from the list which is maintained by the
parser.  This will return C<undef> when there is none left.

=cut

sub popSeparator($) {shift->notImplemented}

#------------------------------------------

=item readSeparator OPTIONS

Read the currently active separator (the last one which was pushed).  The
line (or C<undef>) is returned.  Blank-lines before the separator lines
are ignored.

The return are two scalars, where the first gives the location of the
separator in the file, and the second the line which is found as
separator.  A new separator is activated using the C<pushSeparator> method.

=cut

sub readSeparator($) {shift->notImplemented}

#------------------------------------------

=item readHeader WRAP

Read the whole message-header and return it as list
C<field => value, field => value>.  Mind that some fields will
appear more than once.  The WRAP is the expected length of lines,
but is not yet used.

The first element will represent the position in the file where the
header starts.  The follows the list of headerfield names and bodies.

Example:

  my ($where, @header) = $parser->readHeader(72);

=cut

sub readHeader()    {shift->notImplemented}

#------------------------------------------

=item bodyAsString [,CHARS [,LINES]]

Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of two scalars, the first the location in the file
where the body starts, and the second the string containing the body.

=cut

sub bodyAsString() {shift->notImplemented}

#------------------------------------------

=item bodyAsList [,CHARS [,LINES]]

Try to read one message-body from the file.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of scalars, each containing one line (including
line terminator), preceeded by the location in the file where this
body started.

=cut

sub bodyAsList() {shift->notImplemented}

#------------------------------------------

=item bodyAsFile FILEHANDLE [,CHARS [,LINES]]

Try to read one message-body from the file, and immediately write
it to the specified file-handle.  Optionally, the predicted number
of CHARacterS and/or LINES to be read can be supplied.  These values may be
C<undef> and may be wrong.

The return is a list of two scalars: the location of the body and the
number of lines in the body.

=cut

sub bodyAsFile() {shift->notImplemented}

#------------------------------------------

=item bodyDelayed [,CHARS [,LINES]]

Try to read one message-body from the file, but the data is skipped.
Optionally, the predicted number of CHARacterS and/or LINES to be skipped
can be supplied.  These values may be C<undef> and may be wrong.

The return is a list of three scalars: the location of the body, the
size of the body, and the number of lines in the body.

=cut

sub bodyDelayed() {shift->notImplemented}

#------------------------------------------

=item inDosmode

Returns whether the source file contains CR-LF as line-trailers, which
means we handle DOS/Windows files on a UNIX platform.  This value is
only valid if at least one line of input is read.

=cut

sub inDosmode()   {shift->notImplemented}

#------------------------------------------

=item foldHeaderLine LINE, LENGTH

(Class method) Fold the specified line (which is a header-line with a
structured format) into multiple lines.  Each line is terminated by a
newline.

This method is called by C<Mail::Message::Field::toString()> to
format headers before writing them to a file.

Example:

  my $string = 'From: me; very long comment';
  print Mail::Box::Parser::C->foldHeaderLine($string, 40);

=cut

sub foldHeaderLine($$) {shift->notImplemented}

#------------------------------------------

#sub DESTROY
#{   my $self = shift;
#    $self->SUPER::DESTROY;
#    $self->stop;
#}

#------------------------------------------

=back

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
