
package Mail::Box::Search::Grep;
use base 'Mail::Box::Search';

use strict;
use warnings;

use Carp;

#-------------------------------------------

=head1 NAME

Mail::Box::Search::Grep - select messages within a mail box like grep does

=head1 CLASS HIERARCHY

 Mail::Box::Search::Grep
 is a Mail::Box::Search
 is a Mail::Reporter

=head1 SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open('Inbox');

 my $filter = Mail::Box::Search::Grep->new
    ( $folder, label => 'selected'
    , in => 'BODY', match => qr/abc?d*e/
    );
 my @msgs   = $filter->search($folder);

 my $filter = Mail::Box::Search::Grep
    ->new(field => 'To', match => $my_email);
 if($filter->search($message)) {...}

=head1 DESCRIPTION

Read L<Mail::Box-Overview> first.

=head1 METHOD INDEX

Methods prefixed with an abbreviation are described in
L<Mail::Reporter> (MR), L<Mail::Box::Search> (MBS).

The general methods for C<Mail::Box::Search::Grep> objects:

   MR errors                               printMatchedHead FILEHANDLE...
   MR log [LEVEL [,STRINGS]]            MR report [LEVEL]
      new OPTIONS                       MR reportAll [LEVEL]
  MBS printMatch [FILEHANDLE], HASH    MBS search FOLDER|THREAD|MESSAG...
      printMatchedBody FILEHANDLE...    MR trace [LEVEL]

The extra methods for extension writers:

   MR AUTOLOAD                         MBS inHead PART, HEAD
   MR DESTROY                           MR logPriority LEVEL
  MBS inBody PART, BODY                 MR logSettings
   MR inGlobalDestruction               MR notImplemented

=head1 METHODS

=over 4

=cut

#-------------------------------------------

=item new OPTIONS

Create a grep-like search filter.

 OPTION     DEFINED BY             DEFAULT
 binaries   Mail::Box::Search        0
 decode     Mail::Box::Search        1
 details    Mail::Box::Search::Grep  undef
 field      Mail::Box::Search::Grep  undef
 delayed    Mail::Box::Search        1
 deleted    Mail::Box::Search        0
 in         Mail::Box::Search        <$field?'HEAD':'BODY'>
 label      Mail::Box::Search        undef
 limit      Mail::Box::Search        0
 log        Mail::Reporter           'WARNINGS'
 logical    Mail::Box::Search        'REPLACE'
 match      Mail::Box::Search::Grep  <obligatory>
 multiparts Mail::Box::Search        1
 trace      Mail::Reporter           'WARNINGS'

=over 4

=item * details =E<gt> undef|REF-ARRAY|CODE|'PRINT'|'DELETE'

Store the details about where the match was found.  The search may take
much longer when this feature is enabled.

When an ARRAY is specified it will contain a list of references to hashes.
Each hash contains the information of one match.  A match in a header
line will result in a line with fields C<message>, C<part>, and C<field>, where
the field is a C<Mail::Message::Field> object.  When the match is in
the body the hash will contain a C<message>, C<part>, C<linenr>, and C<line>.

In case of a CODE reference, that routine is called for each match. The
first argument is this search object and the second a reference to same
hash as would be stored in the array.

The C<PRINT> will call C<printMatchedHead> or C<printMatchedBody> when
any matching header resp body line was found.  The output is minimalized
by not reprinting the message info on multiple matches in the same
message.

C<DELETE> will flag
the message to be deleted in case of a match.  When a multipart's part
is matched, the whole message will be flagged for deletion.

=item * field =E<gt> undef|STRING|REGEX|CODE

Not valid in combination with C<in =E<gt> BODY>.
all. The STRING is one full field name (case-insensitive).  Use a REGEX
to select more than one header line to be scanned. CODE is a routine which
is called for each field in the header.   The CODE is called with the header
as first, and the field as second argument.  If the CODE returns true, the
message is selected.

=item * match =E<gt> STRING|REGEX|CODE

The pattern to be search for can be a REGular EXpression, or a STRING.  In
both cases, the match succeeds if it is found anywhere within the selected
fields.

With a CODE reference, that function will be called each field or body-line.
When the result is true, the details are delivered.  The call formats are

 $code->($head, $field);          # for HEAD searches
 $code->($body, $linenr, $line);  # for BODY searches

The C<$head> resp C<$body> are one message's head resp. body object.  The
C<$field> is a header line which matches.  The C<$line> and C<$linenr>
tell the matching line in the body.

Be warned that when you search C<in =E<gt> MESSAGE> the code must accept
both formats.

=back

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{in} ||= ($args->{field} ? 'HEAD' : 'BODY');
    $self->SUPER::init($args);

    my $take = $args->{field};
    $self->{MBSG_field_check}
     = !defined $take         ? sub {1}
     : !ref $take             ? do {$take = lc $take; sub { $_[1] eq $take }}
     :  ref $take eq 'Regexp' ? sub { $_[1] =~ $take }
     :  ref $take eq 'CODE'   ? $take
     : croak "Illegal field selector $take.";

    my $match = $args->{match}
       or croak "No match pattern specified.\n";
    $self->{MBSG_match_check}
     = !ref $match             ? sub { index("$_[1]", $match) >= $[ }
     :  ref $match eq 'Regexp' ? sub { "$_[1]" =~ $match } 
     :  ref $match eq 'CODE'   ? $match
     : croak "Illegal match pattern $match.";

    my $details = $self->{MBS_details} = $args->{details};
    $self->{MBSG_deliver}
     = !defined $details ? undef
     : $details eq 'PRINT'
     ? sub { $self->printMatch($_[0]) }
     : $details eq 'DELETE'
     ? sub { $_[0]->{part}->toplevel->delete(1) }
     : ref $details eq 'ARRAY'
     ? sub { push @$details, $_[0] }
     : ref $details eq 'CODE'
     ? sub { $details->($self, $_[0]) }
     : croak "Where to deliver the details? $details";

   $self;
}

#-------------------------------------------

sub search(@)
{   my ($self, $object, %args) = @_;
    delete $self->{MBSG_last_printed};
    $self->SUPER::search($object, %args);
}

#-------------------------------------------

sub printMatch($;$)
{   my $self = shift;
    my ($out, $match) = @_==2 ? @_ : (select, shift);

      $match->{field}
    ? $self->printMatchedHead($out, $match)
    : $self->printMatchedBody($out, $match)
}

#-------------------------------------------

#=back
#=head1 METHODS for extension writers
#=over 4
#=cut

#-------------------------------------------

sub inHead(@)
{   my ($self, $part, $head, $args) = @_;

    my @details = (message => $part->toplevel, part => $part);
    my ($field_check, $match_check, $deliver)
      = @$self{ qw/MBSG_field_check MBSG_match_check MBSG_deliver/ };

    my $matched = 0;
  LINES:
    foreach my $name ($head->names)
    {   next unless $field_check->($head, $name);
        foreach my $field ($head->get($name))
        {   next unless $match_check->($head, $field);
            $matched++;
            last LINES unless $deliver;  # no deliver: only one match needed
            $deliver->( {@details, field => $field} );
        }
    }

    $matched;
}


#-------------------------------------------

sub inBody(@)
{   my ($self, $part, $body, $args) = @_;

    my @details = (message => $part->toplevel, part => $part);
    my ($field_check, $match_check, $deliver)
      = @$self{ qw/MBSG_field_check MBSG_match_check MBSG_deliver/ };

    my $matched = 0;
    my $linenr  = 0;

  LINES:
    foreach my $line ($body->lines)
    {   $linenr++;
        next unless $match_check->($body, $line);

        $matched++;
        last LINES unless $deliver;  # no deliver: only one match needed
        $deliver->( {@details, linenr => $linenr, line => $line} );
    }

    $matched;
}

#-------------------------------------------

=item printMatchedHead FILEHANDLE, MATCH

=cut

sub printMatchedHead($$)
{   my ($self, $out, $match) = @_;
    my $message = $match->{message};
    my $msgnr   = $message->seqnr;
    my $folder  = $message->folder->name;
    my $lp      = $self->{MBSG_last_printed} || '';

    unless($lp eq "$folder $msgnr")  # match in new message
    {   my $subject = $message->subject;
        $out->print("$folder, message $msgnr: $subject\n");
        $self->{MBSG_last_printed} = "$folder $msgnr";
    }

    my @lines   = $match->{field}->toString;
    my $inpart  = $match->{part}->isPart ? 'p ' : '  ';
    $out->print($inpart, join $inpart, @lines);
    $self;
}

#-------------------------------------------

=item printMatchedBody FILEHANDLE, MATCH

=cut

sub printMatchedBody($$)
{   my ($self, $out, $match) = @_;
    my $message = $match->{message};
    my $msgnr   = $message->seqnr;
    my $folder  = $message->folder->name;
    my $lp      = $self->{MBSG_last_printed} || '';

    unless($lp eq "$folder $msgnr")  # match in new message
    {   my $subject = $message->subject;
        $out->print("$folder, message $msgnr: $subject\n");
        $self->{MBSG_last_printed} = "$folder $msgnr";
    }

    my $inpart  = $match->{part}->isPart ? 'p ' : '  ';
    $out->print(sprintf "$inpart %2d: %s", $match->{linenr}, $match->{line});
    $self;
}

#-------------------------------------------

=back

=head1 SEE ALSO

L<Mail::Box-Overview>

For support and additional documentation, see http://perl.overmeer.net/mailbox/

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.014.

Copyright (c) 2001-2002 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
