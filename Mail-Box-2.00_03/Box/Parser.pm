use strict;
use warnings;

package Mail::Box::Parser;
use base 'Mail::Reporter';
use Carp;

our $VERSION = '2.00_03';

=head1 NAME

Mail::Box::Parser - Reading and writing messages

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

=head2 METHODS

=over 4

=cut

#------------------------------------------

=item defaultParser [PARSER]

(Class method) Returns the parser to be used to parse all subsequent
messages, possibly first setting the parser using the optional argument.
Usually, the parser is autodetected; the C<C>-based parser will be used
when it can be, and the C<Perl>-based parser will be used otherwise.

The PARSER argument allows you to specify a package name to force a
particular parser to be used (such as your own custom parser). You have
to C<use> or C<require> the package yourself before calling this method
with an argument. The parser must be a sub-class of C<Mail::Box::Parser>.

=cut

my $_parser_type;

sub defaultParser(;$)
{   my $class = shift;

    # Select the parser manually?
    if(@_)
    {   $_parser_type = shift;
        return $_parser_type if $_parser_type->isa( __PACKAGE__ );

        confess 'Parser '.ref($_parser_type).' does not extend '
              . __PACKAGE__ . "\n";
    }

    # Already determined which parser we want?
    return $_parser_type if $_parser_type;

    # Try to use C-based parser.
    eval 'require Mail::Box::Parser::C';
warn $@ ? "Use Perl-parser\n" : "Use C parser\n";
warn "$@\n" if $@;
    return $_parser_type = 'Mail::Box::Parser::C' unless $@;

    # Fall-back on Perl-based parser.
    require Mail::Box::Parser::Perl;
    $_parser_type = 'Mail::Box::Parser::Perl';
}

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
 separator         Mail::Box::Parser     undef
 trace             Mail::Reporter        'WARNINGS'

The options specific to C<Mail::Box::Parser> are:

=over 4

=item * filename =E<gt> FILENAME

(Required) The name of the file to be read.

=item * mode =E<gt> OPENMODE

File-open mode, which defaults to C<'r'>, which means `read-only'.
See C<perldoc -f open> for possible modes.

=item * separator =E<gt> 'FROM' | undef

A value of C<undef> indicates that the file does not contain a list of
messages but rather a single message (as MH folders do). If C<FROM> is
used, it indicates that an Mbox-style folder is being read, where each
message begins with a line starting with 'From '.  Typical lines are

   From wouter Tue May 19 15:59 MET 1998
   From piet@example.com Tue May 19 15:59 MET 1998 -0100
   From me@example.nl 19 Mei 2000 GMT

Message-bodies which contain lines starting with 'From' should be
escaped, but not all applications do this. This module uses heuristics to
filter these failures out.

Specify C<undef> if there are no separators to be expected, because
you have only one message per folder, like in MH-like mail-folders.

=back

=cut

sub new(@)
{   my $class       = shift;

    if($class eq __PACKAGE__) 
    {   my $parser = $class->defaultParser;
        warn 'PARSER '.$parser;
        return $parser->new(@_);
    }
    else { return $class->SUPER::new(@_);}
}

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $filename = $args->{filename}
        or confess "Filename obligatory to create a parser.";

    $self->log(NOTICE => "Created parser for $filename");

    $args->{mode}  ||= 'r';
    $args->{trace} ||= 'WARNING';

    $self;
}

#------------------------------------------

=item readHeader

Read the whole message-header and return it as list field => value,
field => value.  Mind that some fields will appear more than once.
The list is preceeded by the C<From>-line, which will be C<undef>
for folder-types which do not have such line.

Example:

  my $parser = Mail::Box::Parser::C->new(filename => 'inbox');
  my ($fromline, @header) = $parser->readHeader;

=cut

sub readHeader()
{   my $class = shift;
    confess "$class does not implement readHeader().";
}

#------------------------------------------

=item inDosmode

Returns whether the source file contains CR-LF as line-trailers, which
means we handle DOS/Windows files on a UNIX platform.  This value is
only valid if at least one line of input is read.

=cut

sub inDosmode()
{   my $class = shift;
    confess "$class does not implement inDosmode().";
}

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

sub foldHeaderLine($$)
{   my ($class, $line, $length) = @_;
    confess "$class does not implement foldHeaderLine().";
}

#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 2.00_00.
Please contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
