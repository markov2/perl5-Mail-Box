
use strict;

package Mail::Box::Index;

use FileHandle;
use File::Copy;

use Mail::Message::Head::Subset;

=head1 NAME

 Mail::Box::Index - Keep index files for messages.

=head1 SYNOPSIS

 $folder->readIndex(...)
 $folder->writeIndex(...)

=head1 DESCRIPTION

Message folders which store their data in one single file per message are
very inefficient for producing subject overviews and for computing message
threads.  The C<Mail::Box::Index> module is able to store and read a the
headers of all messages in one file.

When C<Mail::Box::Index> functionality is enabled by specifying C<keep_index>
when opening a folder, the index file is automatically read.  When
the folder is closed, a new index file is created.

Special care is taken to avoid problems which occur when the user changes
or removes message files without updating the index. If the index is not
trustworthy it will not be used (costing some performance for the reader
of the folder).

=head1 METHOD INDEX

The general methods for C<Mail::Box::Index> objects:

      indexFilename                        readIndex [HEADERCLASS]
      new ARGS                             writeIndex MESSAGE [,MESSAGE]

The extra methods for extension writers:

 

Methods prefixed with an abbreviation are described in the following
manual-pages:

 


=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new ARGS

This method is called by folder classes, and should not be called by
client programs. If you wish to control how indexing occurs, use the
following options when creating a folder.

=over 4

=item * keep_index =E<gt> BOOL

Keep an index file of the specified mailbox, one file per directory.
Using an index file will speed up things considerably, because it avoids
reading all the message files the moment that you open the folder.  When
you open a folder, you can use the index file to retrieve information such
as the subject of each message, instead of having to read possibly
thousands of messages.

=item * index_filename =E<gt> FILENAME

The FILENAME which is used in each directory to store the headers of all
mails. The filename shall not contain a directory path. (e.g. Do not use
C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>.)

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

Returns the index file for a folder.  If the C<keep_index> option was
not specified when the folder was created, this method returns undef.

=cut

sub indexFilename()
{   my $self  = shift;
    $self->{MBI_keep_index} ? $self->{MBI_indexfile} : undef;
}

#-------------------------------------------

=item writeIndex MESSAGE [,MESSAGE]

Write an index file containing the specified messages, but only if the
C<keep_index> option was specified when the folder was created.

=cut

sub writeIndex(@)
{   my $self  = shift;
    my $index = $self->indexFilename or return $self;

    # Remove empty index-file.
    unless(@_)
    {   unlink $index;
        return $self;
    }

    open INDEX, ">$index" or return $self;
    $_->printIndex(\*INDEX) foreach @_;
    close INDEX;

    $self;
}

#-------------------------------------------

=item readIndex [HEADERCLASS]

Read the index file if it exists and the user has specified C<keep_index>
when creating the folder. If that option was not specified, the
C<readIndex> method will not know the filename for the index, and
therefore will not work.

The headers which are read are used to initialize objects created using
the specified HEADERCLASS, which may be different for each folder type.
The default HEADERCLASS is C<Mail::Message::Head::Subset>.

=cut

sub readIndex(;$)
{   my $self  = shift;
    my $index = $self->indexFilename or return ();
    my $type  = shift || 'Mail::Message::Head::Subset';

    open INDEX, $index or return ();

    my @index;
    until(eof INDEX)
    {   my $head    = $type->read(\*INDEX);
        push @index, $head;
    }

    close INDEX;
    @index;
}

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_05.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
