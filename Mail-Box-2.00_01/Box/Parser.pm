use strict;
use warnings;

package Mail::Box::Parser;
use base 'Mail::Reporter';
use Carp;

our $VERSION = '2.00_01';

=head1 NAME

Mail::Box::Parser - Reading and writing messages

=head1 SYNOPSIS

=head1 DESCRIPTION

The Mail::Box::Parser package is part of the Mail::Box suite, which is
capable of parsing folders.  Usually, you won't need to know anything
about this module, except the options which are involved with this code.

There are two implementations of this module:

=over 4

=item * C<Mail::Box::Parser::C>

A fast parser written in C<C>, using C<Inline::C>.  If it is possible to
install C<Inline::C> on your system, this module will automatically be used.
It will be much faster then the other option.

=item * C<Mail::Box::Parser::Perl>

A slower parser which only uses plain Perl.  This module is a bit slower,
and certainly doing less checking and less recovery.

=back

Each implementation supplies the same methods, as are described in this page.

=head2 METHODS

=over 4

=cut

#------------------------------------------

=item defaultParser [PARSER]

(class method) Which parser must be used to parse all next messages.
Usually, this is autodetecting: when the C<C>-based parser can be used,
that package-name will be returned.  Otherwise this will return the name
of the pure perl version of the parser.

With the PARSER-argument, you can specify a package-name to force the
parser to be used, which may be your own.  You have to C<use> or C<require>
the package yourself.  The parser must be a sub-class of C<Mail::Box::Parser>.

=cut

my $_parser_type;

sub defaultParser(;$)
{   my $class = shift;

    if(@_)
    {   $_parser_type = shift;
        return $_parser_type if $_parser_type->isa( __PACKAGE__ );

        confess 'Parser '.ref($_parser_type).' does not extend '
              . __PACKAGE__ . "\n";
    }

    return $_parser_type if $_parser_type;

    eval 'require Mail::Box::Parser::C';
    $_parser_type = __PACKAGE__ . ($@ ? '::Perl' : '::C');
warn "Selected parser $_parser_type.\n";
$_parser_type;
}

#------------------------------------------

=item new [OPTIONS]

Start reading from file to get one message (in case of MH-type folders)
or a list of messages (in case of MBox-type folders)

The OPTIONS can be

 filename          Mail::Box::Parser  <obligatory>
 fold              Mail::Box::Parser  72
 log               Mail::Reporter     'WARNINGS'
 mode              Mail::Box::Parser  'r'
 seperator         Mail::Box::Parser  undef
 trace             Mail::Reporter     'WARNINGS'

The options specific to C<Mail::Box::Parser> are:

=over 4

=item * filename =E<gt> FILENAME

(obligatory) The name of the file to be read.

=item * mode =E<gt> OPENMODE

File-open mode, as accepted by the perl's C<open()> command.  Defaults to
C<'r'>, which means `read-only'.

=item * seperator =E<gt> 'FROM' | undef

Specifies whether we do expect a list of messages in this file (and in
that case in what way they are seperated), or a single message.

C<FROM> should be used for MBox-like folders, where each message
is preluded by a line starting with 'From '.  Typical lines are

   From wouter Tue May 19 15:59 MET 1998
   From piet@example.com Tue May 19 15:59 MET 1998 -0100
   From me@example.nl 19 Mei 2000 GMT

Message-bodies which accidentally contain lines starting with 'From'
must be escaped, however not all application are careful enough.  This
module does use other heuristics to filter these failures out.

Specify C<undef> if there are no seperators to be expected, because
you have only one message per folder, like in MH-like mail-folders.

=item * fold =E<gt> INTEGER

(folder writing only) Automatic fold headerlines larger than this
specified value.  Disabled when set to zero.

=back

=cut

sub new(@)
{   my $class       = shift;

      $class eq __PACKAGE__
    ? $class->defaultParser->new(@_)
    : $class->SUPER::new(@_);
}

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $filename = $args->{filename}
        or confess "Filename obligatory to create a parser.";

    $self->log(NOTICE => "Created parser for $filename");

    $args->{mode}  ||= 'r';
    $args->{fold}    = 72 unless defined $args->{fold};
    $args->{trace} ||= 'WARNING';

    $self;
}

#------------------------------------------

=item foldHeaderLine LINE, LENGTH

(class method) Fold the specified line (which is a header-line with a
structured format) into multiple lines.  Each line is terminated by a
new-line.

This method is called by C<Mail::Message::Field::toString()> to
format headers before writing them to file.

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
