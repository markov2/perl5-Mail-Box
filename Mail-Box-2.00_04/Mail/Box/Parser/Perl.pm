use strict;
use warnings;

# Parse mail-boxes with plain Perl.  See Mail::Box::Parser
#
# Copyright (c) 2001 Mark Overmeer. All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

package Mail::Box::Parser::Perl;
use base 'Mail::Box::Parser';

our $VERSION = '2.00_04';

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

=head1 AUTHOR

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 2.00_04.
Please contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
