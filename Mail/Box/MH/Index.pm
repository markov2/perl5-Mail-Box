
use strict;

package Mail::Box::MH::Index;
use base 'Mail::Reporter';

use Mail::Message::Head::Subset;
use Carp;

=head1 NAME

Mail::Box::MH::Index - keep index files for messages.

=head1 SYNOPSIS

 my $index = Mail::Box::MH::Index->new;
 $index->read(...)
 $index->write(...)

=head1 DESCRIPTION

Message folders which store their data in one single file per message are
very inefficient for producing subject overviews and for computing message
threads.  The Mail::Box::MH::Index object is able to store and read a the
headers of all messages in one file.

When the Mail::Box::MH::Index functionality is enabled by specifying
C<keep_index> when opening a folder, the index file is automatically read.
When the folder is closed, a new index file is created.

Special care is taken to avoid problems which occur when the user changes
or removes message files without updating the index. If the index is not
trustworthy it will not be used (costing some performance for the reader
of the folder).

=head1 METHODS

=cut

#-------------------------------------------

=head2 Initiation

=cut

#-------------------------------------------

=method new OPTIONS

=option  filename FILENAME
=default filename <obligatory>

The FILENAME which is used to store the headers of all the e-mails for
one folder. This must be an absolute pathname.

=option  head_type CLASS
=default head_type 'Mail::Message::Head::Subset'

The type of headers which will be used to store header information when
it is read from the index file.  You can not be sure the index contains
all header line (the mailbox may have been updated without updating
the index) so this will usually be (an sub-class of)
Mail::Message::Head::Subset.

=option  head_wrap INTEGER
=default head_wrap 72

The preferred number of character in each header line.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{MBMI_filename}  = $args->{filename}
       or croak "No index filename specified.";

    $self->{MBMI_head_wrap} = $args->{head_wrap} || 72;
    $self->{MBMI_head_type}
       = $args->{head_type} || 'Mail::Message::Head::Subset';

    $self;
}

#-------------------------------------------

=head2 The Index

=cut

#-------------------------------------------

=method write MESSAGES

Write an index file containing the headers specified MESSAGES
(Mail::Message objects).

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

    my $written    = 0;

    local *INDEX;
    open INDEX, '>', $index or return;

    foreach my $msg (@_)
    {   my $head     = $msg->head;
        next if $head->isDelayed;

        my $filename = $msg->filename;
        $head->setNoRealize($fieldtype->new('X-MailBox-Filename' => $filename));
        $head->setNoRealize($fieldtype->new('X-MailBox-Size'  => -s $filename));
        $head->print(\*INDEX);
        $written++;
    }

    close INDEX;

    unlink $index unless $written;

    $self;
}

#-------------------------------------------

=method read

Read the index file.  The header objects can after this be requested
with the get() method.

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

    $parser->stop;

    $self->{MBMI_index} = \%index;
    $self;
}

#-------------------------------------------

=method get MSGFILE

Look if there is header info for the specified MSGFILE.  The filename
represents one message in folder type which are organized as directory.
This method will return an object of the C<head_type> as specified
during creation of the index object, or C<undef> if the information
is not known or not trustworthy -i.e. the file size changed.

=cut

sub get($)
{   my ($self, $msgfile) = @_;
    $self->{MBMI_index}{$msgfile};
}

#-------------------------------------------

=method filename

Returns the name of the index file.

=cut

sub filename() {shift->{MBMI_filename}}

#-------------------------------------------

1;
