
package Mail::Message::Head::SpamGroup;
use base 'Mail::Message::Head::FieldGroup';

use strict;
use warnings;

=chapter NAME

Mail::Message::Head::SpamGroup - spam fighting related header fields

=chapter SYNOPSIS

 my $sg = Mail::Message::Head::SpamGroup->new(head => $head, ...);
 $head->addSpamGroup($sg);

 my $sg = $head->addSpamGroup( <options> );
 $sg->delete;
 
 my @sgs = $head=>spamGroups;

=chapter DESCRIPTION

A I<spam group> is a set of header fields which are added by spam detection
and spam fighting software.  This class knows various details about
that software.

=chapter METHODS

=section Constructors

=c_method new FIELDS, OPTIONS

Construct an object which maintains one set of fields which were added
by spam fighting software.

=cut

#------------------------------------------

my @implemented = qw/SpamAssassin Habeas-SWE/;

sub implementedTypes() { @implemented }

#------------------------------------------

=method from HEAD|MESSAGE, OPTIONS

Returns a list of C<Mail::Message::Head::SpamGroup> objects, based on the
specified MESSAGE or message HEAD.

=option  types ARRAY-OF-NAMES
=default types C<undef>
Only the specified types will be tried.  If the ARRAY is empty, an empty
list is returned.  Without this option, all sets are returned.

=cut

sub from($@)
{  my ($class, $from, %args) = @_;
   my $head  = $from->isa('Mail::Message::Head') ? $from : $from->head;
   my ($self, @detected);

   my @types = defined $args{types} ? @{$args{types}}
             :                        $class->implementedTypes;

   foreach my $type (@types)
   {   $self = $class->new(head => $head) unless defined $self;
       next unless $self->collectFields($type);

       my ($software, $version);
       if($type eq 'SpamAssassin')
       {   if(my $assassin = $head->get('X-Spam-Checker-Version'))  
           {   # SpamAssassin combine version and subversion.
               ($software, $version) = $assassin =~ m/^(.*)\s+(.*?)\s*$/;
           }
       }
       elsif($type eq 'Habeas-SWE')
       {   ; # no version information, as far as I know
       }
 
       $self->detected($type, $software, $version);
       push @detected, $self;
       undef $self;             # create a new one
   }

   @detected;
}

#------------------------------------------

my $spam_assassin_names = qr/^X-Spam-/i;
my $habeas_swe_names    = qr/^X-Habeas-SWE/i;

sub collectFields($)
{   my ($self, $set) = @_;
    my $scan = $set eq 'SpamAssassin' ? $spam_assassin_names
             : $set eq 'Habeas-SWE'   ? $habeas_swe_names
             : die "No spam set $set.";

    my @names = map { $_->name } $self->head->grepNames($scan);
    return () unless @names;

    $self->addFields(@names);
    @names;
}

#------------------------------------------

=ci_method isSpamGroupFieldName NAME
=cut
sub isSpamGroupFieldName($)
{  local $_ = $_[1];
   $_ =~ $spam_assassin_names || $_ =~ $habeas_swe_names;
}

#------------------------------------------

=ci_method habeasSweFieldsCorrect [MESSAGE|HEAD]
Returns a true value if the MESSAGE or HEAD contains C<Habeas-SWE> fields
which are correct.  Without argument, this is used as instance method on
an existing Spam-Group.

=examples checking Habeas-SWE fields

 if(Mail::Message::Head::SpamGroup->habeasSweFieldsCorrect($message))
 {   $message->label(spam => 0);
 }

 my $sg = $message->head->spamGroups('Habeas-SWE');
 if($sg->habeasSweFieldsCorrect) { ... };

 use List::Util 'first';
 if(first {$_->habeasSweFieldsCorrect} $head->spamGroups)
 {   ...
 }

=cut

my @habeas_lines =
( 'winter into spring', 'brightly anticipated', 'like Habeas SWE (tm)'
, 'Copyright 2002 Habeas (tm)'
, 'Sender Warranted Email (SWE) (tm). The sender of this'
, 'email in exchange for a license for this Habeas'
, 'warrant mark warrants that this is a Habeas Compliant'
, 'Message (HCM) and not spam. Please report use of this'
, 'mark in spam to <http://www.habeas.com/report/>.'
);

sub habeasSweFieldsCorrect(;$)
{   my $self;

    if(@_ > 1)
    {   my ($class, $thing) = @_;
        my $head = $thing->isa('Mail::Message::Head') ? $thing : $thing->head;
        $self    = $head->spamGroups('Habeas-SWE') or return;
    }
    else
    {   $self = shift;
        return unless $self->type eq 'Habeas-SWE';
    }

    my $head     = $self->head;
    return if $self->fields != @habeas_lines;

    for(my $nr=1; $nr <= $#habeas_lines; $nr++)
    {   my $f = $head->get("X-Habeas-SWE-$nr") or return;
        return if $f->unfoldedBody ne $habeas_lines[$nr-1];
    }

    1;
}

#------------------------------------------

=chapter DETAILS

=section Spam fighting fields

=subsection Detected spam fighting software

The M<Mail::Message::Head::SpamGroup> class can be used to detect
fields which were produced by different spam fighting software.

=over 4
=item * SpamAssassin
These fields are added by L<Mail::SpamAssassin>, which is the central
implementation of the spam-assassin package.  The homepage of this
GPL'ed project can be found at L<http://spamassassin.org>.

=item * Habeas-SWE
Habeas tries to fight spam via the standard copyright protection
mechanism: Sender Warranted E-mail (SWE). Only when you have a contract
with Habeas, you are permitted to add a few copyrighted lines to your
e-mail. Spam senders will be refused a contract.  Mail clients which
see these nine lines are (quite) sure that the message is sincere.

See L<http://www.habeas.com> for all the details on this commercial
product.

=back

=cut

1;
