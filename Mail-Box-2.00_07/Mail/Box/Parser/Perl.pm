use strict;
use warnings;

package Mail::Box::Parser::Perl;
use base 'Mail::Box::Parser';

our $VERSION = '2.00_07';

=head1 NAME

 Mail::Box::Parser::Perl - Reading messages in Perl

=head1 CLASS HIERARCHY

 Mail::Box::Parser::Perl
 is a Mail::Box::Parser
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

The C<Mail::Box::Parser::Perl> implements parsing of messages in Perl.
This may be a little slower than the C<C> based parser, but will also
work on platforms where no C compiler is available.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Parser::Perl> objects:

  MBP bodyAsString [,CHARS [,LINES]]   MBP readHeader
  MBP defaultParser [PARSER]           MBP readSeparator OPTIONS
   MR errors                            MR report [LEVEL]
  MBP foldHeaderLine LINE, LENGTH       MR reportAll [LEVEL]
  MBP inDosmode                        MBP setPosition WHERE
   MR log [LEVEL [,STRINGS]]           MBP start OPTIONS
  MBP new [OPTIONS]                    MBP stop
  MBP popSeparator                      MR trace [LEVEL]
  MBP pushSeparator STRING              MR warnings

The extra methods for extension writers:

   MR logPriority LEVEL                 MR logSettings

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBP = L<Mail::Box::Parser>

=head1 METHODS

=over 4

=cut

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $file = new FileHandle $args->{filename}, $args->{mode};
    return unless $file;

    $self->{MBPP_file}      = $file;
    $self->{MBPP_seperator} = $args->{seperator} || undef;
    $self->{MBPP_dosmode}   = 1;
    $self;
}

#------------------------------------------

sub readHeader()
{   my $self = shift;

    my $file = $self->{MMPP_file};
    my $fromline;

    if($self->{MBPP_seperator} eq 'FROM')
    {
         return () unless defined($fromline = <$file>);
         if($fromline !~ m/^From /)
         {   my $count = 0;

             $count++ while defined($fromline = <$file>)
                         && $fromline !~ m/^From /;

             $self->log(ERROR =>
                 "Skipped $count lines to From at ".$file->input_line_number);
         }
         $fromline =~ s/\r?\n$//;
    }

    my @list;
    while(<$file>)
    {   chomp;
        $self->{MMPP_dosmode} = s/\r$// if $self->{MMPP_dosmode};
        last unless length;

        if(@list && m/^\s+/)                   { $list[-1] .= $_ }
        elsif( m/^\s*([^:\s]*)\s*\:\s*(.*)$/ ) { push @list, $1 => $2 }
        else
        {   $self->log(ERROR =>
                "Premature end of headers in line ".$file->input_line_number);
        }
    }

    ($fromline, @list);
}

#------------------------------------------

# sub bodyAsString(;$$)

#------------------------------------------

sub foldHeaderLine($$)
{   my ($class, $line, $length) = @_;
}

#------------------------------------------

sub inDosmode() {shift->{MMPP_dosmode}}

#------------------------------------------
# sub pushSeparator($) {}
# sub popSeparator() {}

#------------------------------------------

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_07.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
