
package Mail::Message::Head::SpamGroup;
use base 'Mail::Message::Head::FieldGroup';

use strict;
use warnings;

use Carp 'confess';

=chapter NAME

Mail::Message::Head::SpamGroup - spam fighting related header fields

=chapter SYNOPSIS

 my $sg = Mail::Message::Head::SpamGroup->new(head => $head, ...);
 $head->addSpamGroup($sg);

 my $sg = $head->addSpamGroup( <options> );
 $sg->delete;
 
 my @sgs = $head->spamGroups;

=chapter DESCRIPTION

A I<spam group> is a set of header fields which are added by spam detection
and spam fighting software.  This class knows various details about
that software.

=chapter METHODS

=section Constructors

=c_method new $fields, %options

Construct an object which maintains one set of fields which were added
by spam fighting software.

=cut

#------------------------------------------

=ci_method knownFighters
Returns an unsorted list of all names representing pre-defined spam-fighter
software.  You can ask details about them, and register more fighters with
the M<fighter()> method.
=cut

my %fighters;
my $fighterfields;    # one regexp for all fields

sub knownFighters() { keys %fighters }

#------------------------------------------

=ci_method fighter $name, [$settings]
Get the $settings of a certain spam-fighter, optionally after setting them.
The L<knownFighters()> method returns the defined names.  The names
are case-sensitive.

=requires fields REGEXP
The regular expression which indicates which of the header fields are
added by the spam fighter software.

=option  version CODE
=default version C<undef>
Can be called to collect the official name and the version of the
software which is used to detect spam.  The CODE ref is called with
the spamgroup object (under construction) and the header which is inspected.

=requires isspam CODE
The CODE must return true or false, to indicate whether the spam fighter
thinks that the message contains spam.  The CODE ref is called with
the spamgroup object (under construction) and the header which is inspected.

=example adding your own spam-fighter definitions
 Mail::Message::Head::SpamGroup->fighter( 'MY-OWN',
    fields => qw/^x-MY-SPAM-DETECTOR-/,
    isspam => sub { my ($sg, $head) = @_; $head->fields > 100 }
   );

=cut

sub fighter($;@)
{   my ($thing, $name) = (shift, shift);

    if(@_)
    {   my %args   = @_;
        defined $args{fields} or confess "Spamfighters require fields\n";
        defined $args{isspam} or confess "Spamfighters require isspam\n";
        $fighters{$name} = \%args;

        my @fields = map { $_->{fields} } values %fighters;
        local $" = '|';
        $fighterfields = qr/@fields/;
    }

    %{$fighters{$name}};
}


BEGIN
{  __PACKAGE__->fighter( SpamAssassin =>
       fields  => qr/^X-Spam-/i
     , isspam  =>
          sub { my ($sg, $head) = @_;
                my $f = $head->get('X-Spam-Flag') || $head->get('X-Spam-Status')
                   or return 0;

                $f =~ m/^yes\b/i;
              }
    , version =>
          sub { my ($sg, $head) = @_;
                my $assin = $head->get('X-Spam-Checker-Version') or return ();
                my ($software, $version) = $assin =~ m/^(.*)\s+(.*?)\s*$/;
                ($software, $version);
              }
    );

  __PACKAGE__->fighter( 'Habeas-SWE' =>
      fields  => qr/^X-Habeas-SWE/i
    , isspam  =>
          sub { my ($sg, $head) = @_;
                not $sg->habeasSweFieldsCorrect;
              }
    );

  __PACKAGE__->fighter( MailScanner  =>
      fields  => qr/^X-MailScanner/i
    , isspam  =>
          sub { my ($sg, $head) = @_;
                my $subject = $head->get('subject');
                $subject =~ m/^\{ (?:spam|virus)/xi;
              }
    );

}

#------------------------------------------

=method from $head|$message, %options

Returns a list of C<Mail::Message::Head::SpamGroup> objects, based on the
specified $message or message $head.

=option  types ARRAY-OF-NAMES
=default types C<undef>
Only the specified types will be tried.  If the ARRAY is empty, an empty
list is returned.  Without this option, all sets are returned.

=cut

sub from($@)
{  my ($class, $from, %args) = @_;
   my $head  = $from->isa('Mail::Message::Head') ? $from : $from->head;
   my ($self, @detected);

   my @types = defined $args{types} ? @{$args{types}} : $class->knownFighters;

   foreach my $type (@types)
   {   $self = $class->new(head => $head) unless defined $self;
       next unless $self->collectFields($type);

       my %fighter = $self->fighter($type);
       my ($software, $version)
           = defined $fighter{version} ? $fighter{version}->($self, $head) : ();
 
       $self->detected($type, $software, $version);
       $self->spamDetected( $fighter{isspam}->($self, $head) );

       push @detected, $self;
       undef $self;             # create a new one
   }

   @detected;
}

#------------------------------------------

sub collectFields($)
{   my ($self, $set) = @_;
    my %fighter = $self->fighter($set)
       or confess "ERROR: No spam set $set.";

    my @names = map { $_->name } $self->head->grepNames( $fighter{fields} );
    return () unless @names;

    $self->addFields(@names);
    @names;
}

#------------------------------------------

=ci_method isSpamGroupFieldName $name
=cut

sub isSpamGroupFieldName($) { $_[1] =~ $fighterfields }

#------------------------------------------

=ci_method habeasSweFieldsCorrect [$message|$head]
Returns a true value if the $message or $head contains C<Habeas-SWE> fields
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
        my $type = $self->type;
        return unless defined $type && $type eq 'Habeas-SWE';
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

=method spamDetected [BOOLEAN]
Returns (after setting) whether this group of spam headers thinks that
this is spam.  See M<Mail::Message::Head::Complete::spamDetected()>.

=examples
  die if $head->spamDetected;

  foreach my $sg ($head->spamGroups)
  {   print $sg->type." found spam\n" if $sg->spamDetected;
  }

=cut

sub spamDetected(;$)
{   my $self = shift;
    @_? ($self->{MMFS_spam} = shift) : $self->{MMFS_spam};
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

=item * MailScanner
The MailScanner filter is developed and maintained by
transtec Computers.  The software is available for free download from
L<http://www.sng.ecs.soton.ac.uk/mailscanner/>.  Commercial support
is provided via L<http://www.mailscanner.biz>.

=back

=cut

1;
