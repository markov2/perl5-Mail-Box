use strict;
use warnings;

package Mail::Message::Field::Flex;
use base 'Mail::Message::Field';

use Carp;

our $VERSION = 2.016;

=head1 NAME

Mail::Message::Field::Flex - one line of a message header

=head1 CLASS HIERARCHY

 Mail::Message::Field::Flex
 is a Mail::Message::Field

=head1 SYNOPSIS

 See L<Mail::Message::Field>

=head1 DESCRIPTION

See L<Mail::Message::Field>.  This is the flexible implementation of
a field: it can easily be extended because it stores its data in a hash
and the constructor (C<new>) and initialiser (C<init>) are split.  However,
you pay the price in performance.  The C<::Fast> packages is faster (as
the name predicts).

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Message::Field> (MMF).

The general methods for C<Mail::Message::Field::Flex> objects:

  MMF addresses                        MMF new ...
  MMF attribute NAME [, VALUE]         MMF print [FILEHANDLE]
  MMF body                             MMF toDate TIME
  MMF comment [STRING]                 MMF toInt
  MMF content                          MMF toString
  MMF folded [ARRAY-OF-LINES]          MMF wellformedName ...
  MMF name

The extra methods for extension writers:

  MMF clone                            MMF nrLines
  MMF isStructured                     MMF setWrapLength CHARS
  MMF newNoCheck NAME, BODY, COMM...   MMF size

=head1 METHODS

=over 4

=cut

#------------------------------------------

sub new($;$$@)
{
    my $class  = shift;
    my ($name, $body, $comment, %args);

    if(@_==2 && ref $_[1] eq 'ARRAY' && !ref $_[1][0])
                 { $name = shift; %args = @{(shift)} }
    elsif(@_>=3) { ($name, $body, $comment, %args) = @_ }
    elsif(@_==2) { ($name, $body) = @_ }
    elsif(@_==1) { $name = shift }
    else         { confess }

    $args{create} = [$name, $body, $comment];
    (bless {}, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;
    my ($name, $body, $comment) = @{$args->{create}};

    #
    # Compose the body.
    #

    if(!defined $body)
    {   # must be one line of a header.
        ($name, $body) = split /\:\s*/, $name, 2;

        unless($body)
        {   warn "No colon in headerline: $name\n";
            $body = '';
        }
    }
    elsif($name =~ m/\:/)
    {   warn "A header-name cannot contain a colon in $name\n";
        return undef;
    }

    if(defined $body && ref $body)
    {   # Objects
        $body = join ', ',
            map {$_->isa('Mail::Address') ? $_->format : "$_"}
                (ref $body eq 'ARRAY' ? @$body : $body);
    }
    
    warn "Header-field name contains illegal character: $name\n"
        if $name =~ m/[^\041-\176]/;

    $body =~ s/\s*\015?\012$//;

    #
    # Take the comment.
    #

    if(defined $comment && length $comment)
    {   # A comment is defined, so shouldn't be in body.
        confess "A header-body cannot contain a semi-colon in $body."
            if $body =~ m/\;/;
    }
    elsif(__PACKAGE__->isStructured($name))
    {   # try strip comment from field-body.
        $comment = $body =~ s/\s*\;\s*(.*)$// ? $1 : undef;
    }

    #
    # Create the object.
    #

    @$self{ qw/MMF_name MMF_body MMF_comment/ } = ($name, $body, $comment);
    $self;
}

#------------------------------------------

sub clone()
{   my $self = shift;
    (ref $self)->new($self->name, $self->body, $self->comment);
}

#------------------------------------------

sub name() { lc shift->{MMF_name}}
sub body() {    shift->{MMF_body}}

#------------------------------------------

sub comment(;$)
{   my $self = shift;
    @_ ? $self->{MMF_comment} = shift : $self->{MMF_comment};
}

#------------------------------------------

sub folded(;$)
{   my $self = shift;
    if(@_)
    {   return unless defined($self->{MMF_folded} = $_[0]);
        return @{ (shift) };
    }
    return @{$self->{MMF_folded}} if defined $self->{MMF_folded};

    my $comment = $self->{MMF_comment};

    $self->{MMF_name} .': '
    . $self->{MMF_body}
    . (defined $comment ? '; '.$comment : '')
    . "\n";
}

#------------------------------------------
#=back
#=head1 METHODS for extension writers
#=over 4
#=cut
#------------------------------------------

sub newNoCheck($$$;$)
{   my $self = bless {}, shift;
    @$self{ qw/MMF_name MMF_body MMF_comment MMF_folded/ } = @_;
    $self;
}

#------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.016.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
