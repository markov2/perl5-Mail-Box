
use strict;
use warnings;

package Mail::Box::MH::Message;
use base 'Mail::Box::Message';

use File::Copy;

=head1 NAME

Mail::Box::MH::Message - a message in a MH-folder

=head1 CLASS HIERARCHY

 Mail::Box::MH::Message
 is a Mail::Box::Message
 is a Mail::Message
 is a Mail::Reporter

=head1 SYNOPSIS

 my $folder = new Mail::Box::MH ...
 my $message = $folder->message(10);

=head1 DESCRIPTION

A C<Mail::Box::MH::Message> represents one message in an MH-folder.

The bottom of this page provides more details about
L<details about the implementation|/"IMPLEMENTATION">, but first the use.

=head1 METHOD INDEX

The general methods for C<Mail::Box::MH::Message> objects:

   MM attach MESSAGES [,OPTIONS]           load CLASS [, ARRAY-OF-LINES]
   MM body [OBJECT]                     MR log [LEVEL [,STRINGS]]
   MM clone                             MM messageId
  MBM coerce FOLDER, MESSAGE [,OP...   MBM modified [BOOL]
  MBM copyTo FOLDER                        new OPTIONS
  MBM delete                            MM parent
  MBM deleted [BOOL]                       print TO
  MBM diskDelete                           printIndex [FILEHANDLE]
   MR errors                               readIndex CLASS [,FILEHANDLE]
      filename [FILENAME]               MR report [LEVEL]
  MBM folder [FOLDER]                   MR reportAll [LEVEL]
   MM guessTimestamp                   MBM seqnr [INTEGER]
   MM head [OBJECT]                    MBM setLabel LIST
   MM isDelayed                        MBM shortString
   MM isDummy                          MBM size
   MM isMultipart                       MM timestamp
   MM isPart                            MM toplevel
  MBM label STRING [ ,STRING ,...]      MR trace [LEVEL]
  MBM labels                            MR warnings

The extra methods for extension writers:

   MR logPriority LEVEL                 MR notImplemented

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MM = L<Mail::Message>
   MR = L<Mail::Reporter>
  MBM = L<Mail::Box::Message>

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Messages in directory-based folders use the following options:

 body              Mail::Message             undef
 deleted           Mail::Box::Message        0
 filename          Mail::Box::MH::Message    undef
 folder            Mail::Box::Message        <required>
 head              Mail::Message             undef
 labels            Mail::Box::Message        []
 log               Mail::Reporter            'WARNINGS'
 messageId         Mail::Message             undef
 modified          Mail::Box::Message        0
 size              Mail::Box::Message        undef
 trace             Mail::Reporter           'WARNINGS'

=over 4

=item * filename =E<gt> FILENAME

The file where the message is stored in.

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{MBM_filename}  = $args->{filename};
    $self;
}

#-------------------------------------------

=item print TO

Write one message to a file-handle.  Unmodified messages are taken
from the folder-file where they were stored in.  Modified messages
are written as in memory.  Specify a file-handle to write TO
(defaults to STDOUT).

=cut

sub print()
{   my $self     = shift;
    my $out      = shift || \*STDOUT;

    my $folder   = $self->folder;
    my $filename = $self->filename;

    # Modified messages are printed as they were in memory.  This
    # may change the order and content of header-lines and (of
    # course) also the body.  If the message's original file
    # unexplainably disappeared, we also print the internally
    # stored message.

    if(!$self->modified && $filename && -r $filename)
    {   copy($filename, $out);
    }
    else
    {   $self->createStatus->createXStatus;
        $self->MIME::Entity::print($out);
    }

    1;
}

#-------------------------------------------

=item printIndex [FILEHANDLE]

Print the information of this message which is required to maintain
an index-file.  By default, this prints to STDOUT.

=cut

sub printIndex(;$)
{   my $self = shift;
    my $out  = shift || \*STDOUT;

    my $head = $self->head || return $self;
    $head->add('X-MailBox-Filename', $self->filename);
    $head->print($out);
    print $out "\n";
    $self;
}

#-------------------------------------------

=item readIndex CLASS [,FILEHANDLE]

Read the headers of one message from the index into a CLASS
structure.  CLASS is (a sub-class of) a MIME::Head.  If no
FILEHANDLE is specified, the data is read from STDIN.

=cut

sub readIndex($;$)
{   my $self  = shift;
    shift->read(shift, shift || \*STDIN);
}

#-------------------------------------------

=item filename [FILENAME]

Returns the name of the file in which this message is actually stored.  This
will return C<undef> when the message is not stored in a file.

=cut

sub filename(;$)
{   my $self = shift;
    @_ ? $self->{MBM_filename} = shift : $self->{MBM_filename};
}

#-------------------------------------------

sub diskDelete()
{   my $self = shift;
    $self->SUPER::diskDelete;
    unlink $self->filename;
    $self;
}


#-------------------------------------------

=item load CLASS [, ARRAY-OF-LINES]

This method is called by the autoloader then the data of the message
is required.  If you specified C<REAL> for the C<take_headers> option
for C<new()>, you did have a MIME::Head in your hands, however this
will be destroyed when the whole message is loaded.

If an array of lines is provided, that is parsed as message.  Otherwise,
the file of the message is opened and parsed.

=cut

sub load($;$)
{   my ($self, $class) = (shift, shift);

    my $folder = $self->folder;
    my $parser = $folder->parser;
    my $new;

    if(@_)
    {   $new = eval {$parser->parse_data(shift)};
        my $error = $@ || $parser->last_error;
        warn "Error: $error" if $error;
    }
    else
    {   my $filename = $self->filename;

        unless(open FILE, $filename)
        {   warn "Cannot find folder $folder message $filename anymore.\n";
            return $self;
        }
        $new = eval {$parser->parse(\*FILE)};
        my $error = $@ || $parser->last_error;
        warn "Error: $error" if $error;
        close FILE;
    }

    my $args = { message => $new };
    (bless $self, $class)->delayedInit($args);
    $folder->toBeThreaded($self);
    $folder->{MB_delayed_loads}--;
    $self;
}

#-------------------------------------------

=back

=head1 IMPLEMENTATION

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_06.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
