
use strict;

package Mail::Message::Head::Delayed;
use base 'Mail::Reporter';

our $VERSION = 2.00_16;

use Object::Realize::Later
    becomes          => 'Mail::Message::Head::Complete',
    warn_realization => 0,
    realize          => 'load',
    believe_caller   => 1;

use Carp;
use Date::Parse;
use Scalar::Util 'weaken';

=head1 NAME

Mail::Message::Head::Delayed - A not-read header of a Mail::Message

=head1 CLASS HIERARCHY

 Mail::Message::Head::Delayed realizes Mail::Message::Head::Complete
 is a Mail::Reporter                   is a Mail::Message::Head
                                       is a Mail::Reporter

=head1 SYNOPSIS

 my Mail::Message::Head::Delayed $delayed = ...;
 $delayed->isa('Mail::Message::Head')  # true
 $delayed->guessBodySize               # undef
 $delayed->isDelayed                   # true

 See Mail::Message::Head

=head1 DESCRIPTION

Read C<Mail::Message::Head>, C<Mail::Message>, and C<Mail::Box-Overview> first.

A C<Mail::Message::Head::Delayed> is used as place-holder, to be replaced
by a C<Mail::Message::Head> when someone accesses the header of a message.

=head1 METHOD INDEX

The general methods for C<Mail::Message::Head::Delayed> objects:

  MMH add ...                              new OPTIONS
  MMH build FIELDS                     MMH nrLines
  MMH count NAME                       MMH print FILEHANDLE
   MR errors                            MR report [LEVEL]
  MMH get NAME [,INDEX]                 MR reportAll [LEVEL]
  MMH isDelayed                        MMH reset NAME, FIELDS
  MMH isMultipart                      MMH set ...
  MMH knownNames                       MMH size
   MR log [LEVEL [,STRINGS]]           MMH timestamp
  MMH modified [BOOL]                  MMH toString
  MMH names                             MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                          MMH load
  MMH addNoRealize FIELD                MR logPriority LEVEL
  MMH clone [FIELDS]                    MR logSettings
  MMH createFromLine                   MMH message [MESSAGE]
  MMH createMessageId                  MMH moveLocation DISTANCE
  MMH fileLocation                      MR notImplemented
  MMH grepNames [NAMES|ARRAY-OF-N...   MMH read PARSER
  MMH guessBodySize                        setNoRealize FIELD
  MMH guessTimestamp                   MMH wrapLength [CHARS]

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MMH = L<Mail::Message::Head>
 MMHC = L<Mail::Message::Head::Complete>

=head1 METHODS

=over 4

=item new OPTIONS

 OPTION      DEFINED BY              DEFAULT
 field_type  Mail::Message::Head     <not used>
 log         Mail::Reporter          'WARNINGS'
 message     Mail::Message::Head     undef
 modified    Mail::Message::Head     <not used>
 trace       Mail::Reporter          'WARNINGS'
 wrap_length Mail::Message::Head     <not used>

No options specific to a C<Mail::Message::Head::Delayed>

=cut

#------------------------------------------

sub init($$)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    if(defined $args->{message})
    {   $self->{MMHD_message} = $args->{message};
        weaken($self->{MMHD_message});
    }

    $self;
}

#------------------------------------------

sub isDelayed(;$) {1}

#------------------------------------------

sub modified(;$)
{   return 0 if @_==1 || !$_[1];
    shift->forceRealize->modified(1);
}

#------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#------------------------------------------

sub read($)
{   my ($self, $parser, $headtype, $bodytype, $wrap)  = @_;

#   $parser->skipHeader not implemented... returns where
    $self->{MMH_where}   = 0;
    $self;
}

#------------------------------------------

sub message(;$)
{   my $self = shift;
    if(@_)
    {   $self->{MMHD_message} = shift;
        weaken($self->{MMHD_message});
    }

    $self->{MMHD_message};
}

#------------------------------------------

sub load() {$_[0] = $_[0]->message->loadHead}

#------------------------------------------

sub guessBodySize() {undef}

#-------------------------------------------

sub guessTimestamp() {undef}

#------------------------------------------

=item setNoRealize FIELD

Set a field, but avoid the loading of a possibly partial header.  This
method does not test the validity of the argument, nor flag the header
as changed.

=cut

sub setNoRealize($)
{   my ($self, $field) = @_;

    my $known = $self->{MMH_fields};
    $known->{$field->name} = $field;
    $field;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_16.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
