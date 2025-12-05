#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Box::MH::Labels;
use parent 'Mail::Reporter';

use strict;
use warnings;

use Log::Report      'mail-box', import => [ qw/__x error fault info/ ];

use Mail::Message::Head::Subset ();

#--------------------
=chapter NAME

Mail::Box::MH::Labels - maintain MH message related labels

=chapter SYNOPSIS

  my $labels = Mail::Box::MH::Labels->new;
  $labels->read(...)
  $labels->write(...)

=chapter DESCRIPTION

MH type message folders use one dedicated file per folder-directory to list
special tags to messages in that folder.  By doing this, mail agents may
avoid parsing all the messages, which is very resource consuming.

Labels can be used to group messages, for instance to reflect which
messages have been read or which look like spam.  Some labels are
predefined, but more can be added without limitation.

=cut

#--------------------
=chapter METHODS

=c_method new %options

=requires filename $file
The $file which is used in each directory to store the headers of all
mails. The filename must be an absolute path.

=error MH labels require a filename.
=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);
	$self->{MBML_filename}  = $args->{filename} or error __x"MH labels require a filename.";
	$self;
}

#--------------------
=section Attributes

=method filename
Returns the name of the index file.
=cut

sub filename() { $_[0]->{MBML_filename} }

#--------------------
=section The Label Table

=method get $msgnr
Look if there is label info for message $msgnr.
=cut

sub get($)
{	my ($self, $msgnr) = @_;
	$self->{MBML_labels}[$msgnr];
}

=method read
Read all label information from the file.  When the file does not exist,
this will return undef.
=cut

sub read()
{	my $self  = shift;
	my $seqfn = $self->filename;

	open my $seq, '<:raw', $seqfn
		or return;

	my @labels;

	local $_;
	while(<$seq>)
	{	s/\s*\#.*$//;
		length or next;

		s/^\s*(\w+)\s*\:\s*// or next;
		my $label = $1;

		my $set   = 1;
		   if($label eq 'cur'   ) { $label = 'current' }
		elsif($label eq 'unseen') { $label = 'seen'; $set = 0 }

		foreach (split /\s+/)
		{	if( /^(\d+)\-(\d+)\s*$/ )
			{	push @{$labels[$_]}, $label, $set foreach $1..$2;
			}
			elsif( /^\d+\s*$/ )
			{	push @{$labels[$_]}, $label, $set;
			}
		}
	}
	$seq->close;
	$self->{MBML_labels} = \@labels;
	$self;
}

=method write @messages
Write the labels related to the specified @messages to the label file.
=fault cannot write MH labels file to $file: $!
=fault error while closing MH labels file $file after write: $!
=cut

sub write(@)
{	my $self     = shift;
	my $filename = $self->filename;

	# Remove when no messages are left.
	unless(@_)
	{	unlink $filename;
		return $self;
	}

	open my $out, '>:raw', $filename
		or fault __x"cannot write MH labels file to {file}", file => $filename;

	$self->print($out, @_);
	close $out
		or fault __x"error while closing MH labels file {file} after write", file => $filename;

	$self;
}

=method append $messages
Append the label information about the specified $messages to the end
of the label file.  The information will not be merged with the
information already present in the label file.

=fault cannot append to MH labels file $file: $!
=fault error while closing MH labels file $file after append: $!
=cut

sub append(@)
{	my $self     = shift;
	my $filename = $self->filename;

	open my $out, '>>:raw', $filename
		or fault __x"cannot append to MH labels file {file}", file => $filename;

	$self->print($out, @_);
	close $out
		or fault __x"error while closing MH labels file {file} after append", file => $filename;

	$self;
}

=method print $fh, $messages
Print the labels of the specified messages to the opened file.
=cut

sub print($@)
{	my ($self, $out) = (shift, shift);

	# Collect the labels from the selected messages.
	my %labeled;
	foreach my $message (@_)
	{	my $labels = $message->labels;
		my $seq    = $message->filename =~ s!.*/!!r;

		push @{$labeled{unseen}}, $seq
			unless $labels->{seen};

		foreach (keys %$labels)
		{	push @{$labeled{$_}}, $seq
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
		print $out "$_:";

		while(@msgs)
		{	my $start = shift @msgs;
			my $end   = $start;
			$end = shift @msgs while @msgs && $msgs[0]==$end+1;

			print $out ($start==$end ? " $start" : " $start-$end");
		}
		print $out "\n";
	}

	$self;
}

1;
