
use strict;

package Mail::Box::MH::Index;
use base 'Mail::Reporter';

use Mail::Message::Head::Subset;
use Carp;

=head1 NAME

Mail::Box::MH::Index - keep index files for messages.

=head1 CLASS HIERARCHY

 Mail::Box::MH::Index
 is a Mail::Reporter

=head1 SYNOPSIS

 my $index = Mail::Box::MH::Index->new;
 $index->read(...)
 $index->write(...)

=head1 DESCRIPTION

Message folders which store their data in one single file per message are
very inefficient for producing subject overviews and for computing message
threads.  The C<Mail::Box::MH::Index> module is able to store and read a the
headers of all messages in one file.

When C<Mail::Box::MH::Index> functionality is enabled by specifying
C<keep_index> when opening a folder, the index file is automatically read.
When the folder is closed, a new index file is created.

Special care is taken to avoid problems which occur when the user changes
or removes message files without updating the index. If the index is not
trustworthy it will not be used (costing some performance for the reader
of the folder).

=head1 METHOD INDEX

The general methods for C<Mail::Box::MH::Index> objects:

   MR errors                            MR report [LEVEL]
      get MSGFILE                       MR reportAll [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR trace [LEVEL]
      new OPTIONS                       MR warnings
      read                                 write MESSAGES

The extra methods for extension writers:

   MR AUTOLOAD                          MR inGlobalDestruction
   MR DESTROY                           MR logPriority LEVEL
      filename                          MR logSettings

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

This method is called by folder classes, and should not be called by
client programs. If you wish to control how indexing occurs, use the
following options when creating a folder.

 OPTION      DEFINED BY             DEFAULT
 filename    Mail::Box::MH::Index   '.index'
 log         Mail::Reporter         'WARNINGS'
 trace       Mail::Reporter         'WARNINGS'
 head_wrap   Mail::Box::MH::Index   72

Only useful to write extension to C<Mail::Box::MH::Index>.  Common users of
folders you will not specify these:

 OPTION      DEFINED BY             DEFAULT
 head_type   Mail::Box::MH::Index   'Mail::Message::Head::Subset'

=over 4

=item * filename =E<gt> FILENAME

The FILENAME which is used in each directory to store the headers of all
mails. The filename shall not contain a directory path. (e.g. Do not use
C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>.)

=item * head_type =E<gt> CLASS

The type of headers which will be used to store header information when
it is read from the index file.  You can not be sure the index contains
all header line (the mailbox may have been updated without updating
the index) so this will usually be (an sub-class of)
C<Mail::Message::Head::Subset>.

=item * head_wrap =E<gt> INTEGER

The preferred number of character in each header line.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{MBMI_filename}  = $args->{filename}  || '.index';
    $self->{MBMI_head_wrap} = $args->{head_wrap} || 72;

    $self->{MBMI_head_type}
       = $args->{head_type} || 'Mail::Message::Head::Subset';

    $self;
}

#-------------------------------------------

=item write MESSAGES

Write an index file containing the headers specified MESSAGES
(C<Mail::Message> objects).

=cut

sub write(@)
{   my $self      = shift;
    my $index     = $self->filename or return $self;
    my $fieldtype = 'Mail::Message::Field';

    # Remove empty index-file.
    unless(@_)
    {   unlink $index;
        return $self;
    }

    local *INDEX;
    open INDEX, '>', $index or return;

    foreach my $msg (@_)
    {   my $head     = $msg->head;
        my $filename = $msg->filename;
        $head->setNoRealize($fieldtype->new('X-MailBox-Filename' => $filename));
        $head->setNoRealize($fieldtype->new('X-MailBox-Size'  => -s $filename));
        $head->print(\*INDEX);
    }

    close INDEX;
    $self;
}

#-------------------------------------------

=item read

Read the index file.  The header objects can after this be requested
with the C<get()> method.

=cut

sub read(;$)
{   my $self     = shift;
    my $filename = $self->{MBMI_filename};

    my $parser   = Mail::Box::Parser->new
      ( filename => $filename
      , mode     => 'r'
      ) or return;

    my @options  = ($self->logSettings, wrap_length => $self->{MBMI_head_wrap});
    my $type     = $self->{MBMI_head_type};
    my $index_age= -M $filename;
    my %index;

    while(my $head = $type->new(@options)->read($parser))
    {   my $msgfile = $head->get('x-mailbox-filename');
        my $size    = int $head->get('x-mailbox-size');
        next unless -f $msgfile && -s _ == $size;
        next if defined $index_age && -M _ >= $index_age;

        $index{$msgfile} = $head;
    }

    $self->{MBMI_index} = \%index;
    $self;
}

#-------------------------------------------

=item get MSGFILE

Look if there is header info for the specified MSGFILE.  The filename
represents one message in folder type which are organized as directory.
This method will return an object of the C<head_type> as specified
during creation of the index object, or C<undef> if the information
is not known or not trustworthy -i.e. the filesize changed.

=cut

sub get($)
{   my ($self, $msgfile) = @_;
    $self->{MBMI_index}{$msgfile};
}

#-------------------------------------------

=back

=head1 METHODS for extension writers

=over 4

=cut

#-------------------------------------------

=item filename

Returns the name of the index file.

=cut

sub filename() {shift->{MBMI_filename}}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.007.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
