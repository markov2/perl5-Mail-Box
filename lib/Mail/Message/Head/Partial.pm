
use strict;

package Mail::Message::Head::Partial;
use base 'Mail::Message::Head::Complete';

use Scalar::Util 'weaken';

=chapter NAME

Mail::Message::Head::Partial - subset of header information of a message

=chapter SYNOPSIS

 my $partial = $head->strip;
 $partial->isa('M<Mail::Message::Head>')  # true
 $partial->isDelayed                      # false
 $partial->isPartial                      # true

 $partial->removeFields( qr/^X-/ );
 $partial->removeFieldsExcept( qw/To From/ );
 $partial->removeResentGroups;
 $partial->removeListGroup;
 $partial->removeSpamGroups;

=chapter DESCRIPTION

Header information consumes a considerable amount of memory.  Most of this
information is only useful during a short period of time in your program,
or sometimes it is not used at all.  You then can decide to remove most
of the header information.  However, be warned that it will be lost
permanently: the header (and therefore the message) gets mutulated!

=chapter METHODS

=section Access to the header

=method removeFields <STRING|Regexp>, ...
Remove the fields from the header which are exactly named 'STRING' (case
insensitive) or match the REGular EXPresssion.  Do not forget to add the
'i' modifier to the Regexp, because fields are case insensitive.

See also M<removeField()> which is used to remove one field object from
the header.  The reverse specification can be made with
C<removeFieldsExcept()>.

=examples

 $head->removeFields('bcc', 'received');
 $head->removeFields( qr/^content-/i );

=cut

sub removeFields(@)
{   my $self  = shift;
    my $known = $self->{MMH_fields};

    foreach my $match (@_)
    {
        if(ref $match)
             { $_ =~ $match && delete $known->{$_} foreach keys %$known }
        else { delete $known->{lc $match} }
    }

    $self->cleanupOrderedFields;
}

=method removeFieldsExcept STRING|Regexp, ...
Remove all fields from the header which are not equivalent to one of the
specified STRINGs (case-insensitive) and which are not matching one of
the REGular EXPressions.  Do not forget to add the 'i' modifier to the
Regexp, because fields are case insensitive.

See also M<removeField()> which is used to remove one field object from
the header.  The reverse specification can be made with C<removeFields()>.

=example

 $head->removeFieldsExcept('subject', qr/^content-/i ); 
 $head->removeFieldsExcept( qw/subject to from sender cc/ );

=cut

sub removeFieldsExcept(@)
{   my $self   = shift;
    my $known  = $self->{MMH_fields};
    my %remove = map { ($_ => 1) } keys %$known;

    foreach my $match (@_)
    {   if(ref $match)
        {   $_ =~ $match && delete $remove{$_} foreach keys %remove;
        }
        else { delete $remove{lc $match} }
    }

    delete @$known{ keys %remove };

    $self->cleanupOrderedFields;
}

#------------------------------------------

=method removeResentGroups

Removes all header lines which are member of a I<resent group>, which
are explained in M<Mail::Message::Head::ResentGroup>.  Returned is the
number of removed lines.

For removing single groups (for instance because you want to keep the
last), use M<Mail::Message::Head::FieldGroup::delete()>.

=cut

sub removeResentGroups()
{   my $self = shift;
    require Mail::Message::Head::ResentGroup;

    my $known = $self->{MMH_fields};
    my $found = 0;
    foreach my $name (keys %$known)
    {   next unless Mail::Message::Head::ResentGroup
                         ->isResentGroupFieldName($name);
        delete $known->{$name};
        $found++;
    }

    $self->cleanupOrderedFields;
    $self->modified(1) if $found;
    $found;
}

#------------------------------------------

=method removeListGroup

Removes all header lines which are used to administer mailing lists.
Which fields that are is explained in M<Mail::Message::Head::ListGroup>.
Returned is the number of removed lines.

=cut

sub removeListGroup()
{   my $self = shift;
    require Mail::Message::Head::ListGroup;

    my $known = $self->{MMH_fields};
    my $found = 0;
    foreach my $name (keys %$known)
    {   next unless Mail::Message::Head::ListGroup->isListGroupFieldName($name);
        delete $known->{$name};
	$found++;
    }

    $self->cleanupOrderedFields if $found;
    $self->modified(1) if $found;
    $found;
}

#------------------------------------------

=method removeSpamGroups

Removes all header lines which were produced by spam detection and
spam-fighting software.  Which fields that are is explained in
M<Mail::Message::Head::SpamGroup>.  Returned is the number of removed lines.

=cut

sub removeSpamGroups()
{   my $self = shift;
    require Mail::Message::Head::SpamGroup;

    my $known = $self->{MMH_fields};
    my $found = 0;
    foreach my $name (keys %$known)
    {   next unless Mail::Message::Head::SpamGroup->isSpamGroupFieldName($name);
        delete $known->{$name};
	$found++;
    }

    $self->cleanupOrderedFields if $found;
    $self->modified(1) if $found;
    $found;
}

#------------------------------------------

=method cleanupOrderedFields

The header maintains a list of fields which are ordered in sequence of
definition.  It is required to maintain the header order to keep the
related fields of resent groups together.  The fields are also included
in a hash, sorted on their name for fast access.

The references to field objects in the hash are real, those in the ordered 
list are weak.  So when field objects are removed from the hash, their
references in the ordered list are automagically undef'd.

When many fields are removed, for instance with M<removeFields()> or
M<removeFieldsExcept()>, then it is useful to remove the list of undefs
from the ordered list as well.  In those cases, this method is called
automatically, however you may have your own reasons to call this method.

=cut

sub cleanupOrderedFields()
{   my $self = shift;
    my @take = grep { defined $_ } @{$self->{MMH_order}};
    weaken($_) foreach @take;
    $self->{MMH_order} = \@take;
    $self;
}

#------------------------------------------

=chapter DETAILS

=section Reducing the header size

A message header is very large in memory and quite large on disk, and
therefore a good candidate for size reduction.  One way to reduce the
size is by simply eliminating superfluous header fields.  Each field
requires at least 100 bytes of run-time memory, so this may help!

Before you start playing around with M<removeFields()> and
M<removeFieldsExcept()>, you may take a look at two large groups
of fields which can be removes as sets: the resent headers and the
mailinglist headers.

Resent headers describe the intermediate steps in the transmission
process for the messages.  After successful delivery, they are rarely
useful.

When you are archiving a mailinglist, it is hardly ever useful to
store a the list administration lines for each message as well.

=example see examples/reduce.pl in distribution

 foreach my $msg ($folder->messages)
 {  $msg->head->removeResentGroups;
    $msg->head->removeResentList;
 }

=cut

#------------------------------------------

1;
