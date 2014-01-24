
package Mail::Box::MH::Index;
use base 'Mail::Reporter';

use strict;
use warnings;

use Mail::Message::Head::Subset;
use Carp;

=chapter NAME

Mail::Box::MH::Index - keep index files for messages.

=chapter SYNOPSIS

 my $index = Mail::Box::MH::Index->new;
 $index->read(...)
 $index->write(...)

=chapter DESCRIPTION

Message folders which store their data in one single file per message are
very inefficient for producing subject overviews and for computing message
threads.  The C<Mail::Box::MH::Index> object is able to store and read a the
headers of a set of C<Mail::Box::MH::Message> messages which are
part of a single C<Mail::Box::MH> folder in one file.

When the C<Mail::Box::MH::Index> functionality is enabled by specifying
M<Mail::Box::MH::new(keep_index)> when opening a folder, the index file
is automatically read.  When the folder is closed, a new index file is
created.

Special care is taken to avoid problems which occur when the user changes
or removes message files without updating the index. If the index is not
trustworthy it will not be used (costing some performance for the reader
of the folder).

=chapter METHODS

=section Constructors

=cut

#-------------------------------------------

=c_method new %options

=requires filename FILENAME

The FILENAME which is used to store the headers of all the e-mails for
one folder. This must be an absolute pathname.

=option  head_type CLASS
=default head_type M<Mail::Message::Head::Subset>

The type of headers which will be used to store header information when
it is read from the index file.  You can not be sure the index contains
all header line (the mailbox may have been updated without updating
the index) so this will usually be (an sub-class of)
M<Mail::Message::Head::Subset>.

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

=section The Index

=method filename
Returns the name of the index file.

=cut

sub filename() {shift->{MBMI_filename}}

#-------------------------------------------

=method write $messages
Write an index file containing the headers specified $messages
(M<Mail::Message> objects).
=cut

sub write(@)
{   my $self  = shift;
    my $index = $self->filename or return $self;

    # Remove empty index-file.
    unless(@_)
    {   unlink $index;
        return $self;
    }

    local *INDEX;
    open INDEX, '>:raw', $index
        or return $self;

    my $fieldtype = 'Mail::Message::Field';
    my $written    = 0;

    foreach my $msg (@_)
    {   my $head     = $msg->head;
        next if $head->isDelayed && $head->isa('Mail::Message::Head::Subset');

        my $filename = $msg->filename;
        print INDEX "X-MailBox-Filename: $filename\n"
                  , 'X-MailBox-Size: ', (-s $filename), "\n";

        $head->print(\*INDEX);
        $written++;
    }

    close INDEX;

    $written or unlink $index;

    $self;
}

#-------------------------------------------

=method append $messages
Append $messages to the index file.
=cut

sub append(@)
{   my $self      = shift;
    my $index     = $self->filename or return $self;

    local *INDEX;
    open INDEX, '>>:raw', $index
        or return $self;

    my $fieldtype = 'Mail::Message::Field';

    foreach my $msg (@_)
    {   my $head     = $msg->head;
        next if $head->isDelayed && $head->isa('Mail::Message::Head::Subset');

        my $filename = $msg->filename;
        print INDEX "X-MailBox-Filename: $filename\n"
                  , 'X-MailBox-Size: ', (-s $filename), "\n";

        $head->print(\*INDEX);
    }

    close INDEX;
    $self;
}

#-------------------------------------------

=method read

Read the index file.  The header objects can after this be requested
with the M<get()> method.

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
    {
        # cleanup the index from files which were renamed
        my $msgfile = $head->get('x-mailbox-filename');
        my $size    = int $head->get('x-mailbox-size');
        next unless -f $msgfile && -s _ == $size;
        next if defined $index_age && -M _ < $index_age;

        # keep this one
        $index{$msgfile} = $head;
    }

    $parser->stop;

    $self->{MBMI_index} = \%index;
    $self;
}

#-------------------------------------------

=method get $msgfile

Look if there is header info for the specified $msgfile.  The filename
represents one message in folder type which are organized as directory.
This method will return an object of the M<new(head_type)> as specified
during creation of the index object, or C<undef> if the information
is not known or not trustworthy -i.e. the file size changed.

=cut

sub get($)
{   my ($self, $msgfile) = @_;
    $self->{MBMI_index}{$msgfile};
}

#-------------------------------------------

=section Error handling

=cut

1;
