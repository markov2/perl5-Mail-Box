
use strict;
use v5.6.0;

package Mail::Box::Index;
our $VERSION = v0.4;

use FileHandle;
use File::Copy;

=head1 NAME

Mail::Box::Index - Keep indexfiles on messages.

=head1 SYNOPSIS

   $folder->readIndex(...)
   $folder->printIndex(...)

=head1 DESCRIPTION

Message-folders which store their data in one single file per message
are very inefficient for producing subject overviews and detecting
message-threads.  The Mail::Box::Index is able to store and read a
the headers of all messages in one file.

When Mail::Box::Index functionality is switched on (specify C<keep_index>
when creating a folder), the index-file is automatically read.  When
the folder is closed, a new index-file is created.

Special care is taken to avoid a problems when the user changed or
removed message-files without updating the index.  If the index is
not trusted, it will not be used (and so cost performance to the reader
of the folder).

=head1 PUBLIC INTERFACE

=over 4

=cut

#-------------------------------------------

=item new ARGS

You will not call this method yourself, unless you implement a folder
yourself.  The following options can be specified when you create a
folder.

=over 4

=item * keep_index => BOOL

Keep an index-file in the specified file, one file per directory.  Using
an index-file will speed-up things considerably, because it avoids
that all message-files have to be read on the moment that you open the
folder.  When you open a folder, you need information like the the
subject of each message, and it is not pleasant to open all thousands
of messages to read them.

=item * index_filename => FILENAME

The FILENAME which is used in each directory to store the headers of
all mails.  The filename shall not contain a directory path (so: do not
use C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>)

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{MBI_keep_index} = $args->{keep_index}     || 0;
    $self->{MBI_indexfile}  = $args->{index_filename} || '.index';
    $self;
}

#-------------------------------------------

=item indexFilename

Returns the index-file for a folder.  If the C<keep_index> option was
not used when the folder was read, this returns undef.

=cut

sub indexFilename()
{   my $self  = shift;
    $self->{MBI_keep_index} ? $self->{MBI_indexfile} : undef;
}

#-------------------------------------------

=item writeIndex MESSAGE [,MESSAGE]

Write an index-file containing the specified messages, but only if the
user requested it: the C<keep_index> option of C<new()> must have been
specified.

=cut

sub writeIndex(@)
{   my $self = shift;
    my $index = $self->indexFilename or return $self;

    open INDEX, '>', $index or return $self;

    foreach (@_)
    {   $_->printIndex(\*INDEX);
        print INDEX "\n";
    }

    close INDEX;
    $self;
}

#-------------------------------------------

=item readIndex [HEADERCLASS]

Read the index-file if it exists and the user has specified C<keep_index>
with the constructor (C<new>) of this folder.  If that option is not
specified, the C<readIndex> does not know under what name the index is
stored, and therefore not work.

The headers which are read are created into the specified HEADERCLASS,
which may be different for each folder-type, but by default a
MIME::Head.

=cut

sub readIndex(;$)
{   my $self  = shift;
    my $index = $self->indexFilename or return ();
    my $type  = shift || 'MIME::Head';

    open INDEX, '<', $index or return ();

    my @index;
    until(eof INDEX)
    {   my $head    = $type->read(\*INDEX);
        my $message = $type->new( head => $head );
        push @index, $message;
    }

    close INDEX;
    @index;
}

=back

=head1 AUTHOR

Mark Overmeer (F<Mark@Overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is alpha, version 0.4

=cut

1;
