
use strict;

package Mail::Box::MH::Labels;
use base 'Mail::Reporter';

use Mail::Message::Head::Subset;

use FileHandle;
use File::Copy;

=head1 NAME

Mail::Box::MH::Labels - process file which maintains message related labels

=head1 CLASS HIERARCHY

 Mail::Box::MH::Labels
 is a Mail::Reporter

=head1 SYNOPSIS

 my $labels = Mail::Box::MH::Labels->new;
 $labels->read(...)
 $labels->write(...)

=head1 DESCRIPTION

MH type message folders use one dedicated file per folder-directory to list
special tags to messages in that folder.  By doing this, mail agents may
avoid parsing all the messages, which is very resource consuming.

Labels can be used to group messages, for instance to reflect which
messages have been read or which look like spam.

Typically, the file which contains the labels is called C<.mh_sequences>.
The MH messages are numbered from C<1>.  As example content for
C<.mh_sequences>:

   cur: 93
   unseen: 32 35-56 67-80

To generalize labels on messages, two are treated specially:

=over 4

=item * cur

The C<cur> specifies the number of the message where the user stopped
reading mail from this folder at last access.  Internally in these
modules refered to as label C<current>.

=item * unseen

With C<unseen> is listed which message was never read.
This must be a mistake in the design of MH: it must be a source of
confusion.  People should never use labels with a negation in the
name:

    if($seen)           if(!$unseen)    #yuk!
    if(!$seen)          if($unseen)
    unless($seen)       unless($unseen) #yuk!

So: label C<unseen> is translated into C<seen> for internal use.

=head1 METHOD INDEX

The general methods for C<Mail::Box::MH::Labels> objects:

   MR errors                            MR report [LEVEL]
   MR log [LEVEL [,STRINGS]]            MR reportAll [LEVEL]
   MR new OPTIONS                       MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                          MR logPriority LEVEL
   MR DESTROY                           MR logSettings
   MR inGlobalDestruction               MR notImplemented

Prefixed methods are described in   MR = L<Mail::Reporter>.

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

This method is called by folder classes, and should not be called by
client programs. If you wish to control how indexing occurs, use the
following options when creating a folder.

 OPTION         DEFINED BY         DEFAULT
 filename       Mail::Box::Index   '.mh_sequences'
 log            Mail::Reporter     'WARNINGS'
 trace          Mail::Reporter     'WARNINGS'

Only useful to write extension to C<Mail::Box::MH::Labels>.  Common users of
folders you will not specify these:

 OPTION         DEFINED BY         DEFAULT

=over 4

=item * filename =E<gt> FILENAME

The FILENAME which is used in each directory to store the headers of all
mails. The filename shall not contain a directory path. (e.g. Do not use
C</usr/people/jan/.index>, nor C<subdir/.index>, but say C<.index>.)

=back

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->{MBML_filename}  = $args->{filename}  || '.mh_sequences';

    $self;
}

#-------------------------------------------

=item read

Read all label information from file.

=cut

sub read()
{   my $self = shift;
    my $seq  = $self->filename;

    open SEQ, '<', $seq
       or return;

    my @labels;

    local $_;
    while(<SEQ>)
    {   s/\s*\#.*$//;
        next unless length;

        next unless s/^\s*(\w+)\s*\:\s*//;
        my $label = $1;

        my $set   = 1;
           if($label eq 'cur'   ) { $label = 'current' }
        elsif($label eq 'unseen') { $label = 'seen'; $set = 0 }

        foreach (split /\s+/)
        {   if( /^(\d+)\-(\d+)\s*$/ )
            {   push @{$labels[$_]}, $label, $set foreach $1..$2;
            }
            elsif( /^\d+\s*$/ )
            {   push @{$labels[$_]}, $label, $set;
            }
        }
    }

    close SEQ;

    $self->{MBML_labels} = \@labels;
    $self;
}

#-------------------------------------------

=item write MESSAGES

Write the labels related to the specified messages to the label file.

=cut

sub write(@)
{   my $self     = shift;
    my $filename = $self->filename;

    # Remove when no messages are left.
    unless(@_)
    {   unlink $filename;
        return $self;
    }

    my $out      = FileHandle->new($filename, 'w') or return;
    $self->print($out, @_);
    $out->close;
    $self;
}

#-------------------------------------------

=item append MESSAGES

Append the label information about the specified MESSAGES to the end
of the label file.  The information will not be merged with the
information already present in the label file.

=cut

sub append(@)
{   my $self     = shift;
    my $filename = $self->filename;

    my $out      = FileHandle->new($filename, 'a') or return;
    $self->print($out, @_);
    $out->close;
    $self;
}

#-------------------------------------------

=item print FILEHANDLE, MESSAGES

Print the messages to the specified open file.

=cut

sub print($@)
{   my ($self, $out) = (shift, shift);

    # Collect the labels from the selected messages.
    my %labeled;
    foreach my $message (@_)
    {   my $labels = $message->labels;
        (my $seq   = $message->filename) =~ s!.*/!!;

        push @{$labeled{unseen}}, $seq
            unless $labels->{seen};

        foreach (keys %$labels)
        {   push @{$labeled{$_}}, $seq
                if $labels->{$_};
        }
    }
    delete $labeled{seen};

    # Write it out

    local $"     = ' ';
    foreach (sort keys %labeled)
    {
        my @msgs = @{$labeled{$_}};  #they are ordered already.
        $_ = 'cur' if $_ eq 'current';
        print $out  "$_:";

        while(@msgs)
        {   my $start = shift @msgs;
            my $end   = $start;

            $end = shift @msgs
                 while @msgs && $msgs[0]==$end+1;

            print $out ($start==$end ? " $start" : " $start-$end");
        }
        print $out "\n";
    }

    $self;
}

#-------------------------------------------

=item get MSGNR

Look if there is label info for message MSGNR.

=cut

sub get($)
{   my ($self, $msgnr) = @_;
    $self->{MBML_labels}[$msgnr];
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

sub filename() {shift->{MBML_filename}}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.006.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
