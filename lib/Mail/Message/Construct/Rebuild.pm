
use strict;

package Mail::Message;

use Mail::Message::Head::Complete;
use Mail::Message::Body::Lines;
use Mail::Message::Body::Multipart;

use Mail::Address;
use Scalar::Util    'blessed';
use List::Util      'first';
use Mail::Box::FastScalar;

=chapter NAME

Mail::Message::Construct::Rebuild - modify a Mail::Message

=chapter SYNOPSIS

 my $cleanup = $msg->rebuild;

=chapter DESCRIPTION

Modifying existing messages is a pain, certainly if this has to be
done in an automated fashion.  The problems are especially had when
multiparts have to be created or removed.  The M<rebuild()> method
tries to simplify this task and add some standard features.

=chapter METHODS

=section Constructing a message

=method rebuild %options

Reconstruct an existing message into something new.  Returned is a new
message when there were modifications made, C<undef> if the message has
no body left, or the original message when no modifications had to be
made.

Examples of use: you have a message which only contains html, and you
want to translate it into a multipart which contains the original html
and the textual translation of it.  Or, you have a message with parts
flagged to be deleted, and you want those changes be incorparted in the
memory structure.  Another possibility: clear all the resent groups
(see M<Mail::Message::Head::ResentGroup>) from the header, before it is
written to file.

Reconstructing is a hazardous task, where multi level multiparts and
nested messages come into play.  The rebuild method tries to simplify
handing these messages for you.

=option  keep_message_id BOOLEAN
=default keep_message_id <false>
The message-id is an unique identification of the message: no two messages
with different content shall exist anywhere.  However in practice, when
a message is changed during transmission, the id is often incorrectly
not changed.  This may lead to complications in application which see
both messages with the same id.

=option  rules ARRAY
=default rules <see text>
The ARRAY is a list of rules, which each describe an action which will
be called on each part which is found in the message.  Most rules
probably won't match, but some will bring changes to the content.
Rules can be specified as method name, or as code reference.  See the
L</DETAILS> chapter in this manual page, and M<recursiveRebuildPart()>.

By default, only the relatively safe transformations are performed:
C<replaceDeletedParts>, C<descendMultiparts>, C<descendNested>,
C<flattenMultiparts>, C<flattenEmptyMultiparts>.  In the future, more
safe transformations may be added to this list.

=option  extra_rules ARRAY
=default extra_rules []
The standard set of rules, which is the default for the C<rules> option,
is a moderest setting.  In stead of copying that list into a full set
of rules of your own, you can also specify only some additional rules
which will be prependend to the default rule set.

The order of the rules is respected, which means that you do not always
need to rewrite the whole rule is (see C<rule> option).  For instance,
the extra rule of C<removeDeletedParts> returns an C<undef>, which
means that it cancels the effect of the default rule C<replaceDeletedParts>.

=examples

 # remove all deleted parts
 my $cleaned = $msg->rebuild(keep_message_id => 1);
 $folder->addMessage($cleaned) if defined $cleaned;

 # Replace deleted parts by a place-holder
 my $cleaned = $msg->rebuild
   ( keep_message_id => 1
   , extra_rules => [ 'removeEmpty', 'flattenMultiparts' ]
   );

=error No rebuild rule $name defined.
=cut

my @default_rules =
  qw/replaceDeletedParts descendMultiparts descendNested
     flattenMultiparts flattenEmptyMultiparts/;

sub rebuild(@)
{   my ($self, %args) = @_;
 
    # Collect the rules to be run

    my @rules   = $args{rules} ? @{$args{rules}} : @default_rules;
    unshift @rules, @{$args{extra_rules}} if $args{extra_rules};
    unshift @rules, @{$args{extraRules}}  if $args{extraRules}; #old name

    foreach my $rule (@rules)
    {   next if ref $rule;
        unless($self->can($rule))
        {   $self->log(ERROR => "No rebuild rule '$rule' defined.\n");
            return 1;
        }
    }

    # Start off with the message

    my $rebuild = $self->recursiveRebuildPart($self, rules => \@rules)
        or return;

    # Be sure we end-up with a message

    if($rebuild->isa('Mail::Message::Part'))
    {   # a bit too much information is lost: we are left without the
        # main message headers....
        my $clone = Mail::Message->new(head => $self->head->clone);
        $clone->body($rebuild->body);  # to update the Content lines
        $rebuild = $clone;
    }

    $args{keep_message_id} or $rebuild->takeMessageId;
    $rebuild;
}

#------------------------------------------
# The general rules

sub flattenNesting($@)
{   my ($self, $part) = @_;
    $part->isNested ? $part->body->nested : $part;
}

sub flattenMultiparts($@)
{   my ($self, $part) = @_;
    return $part unless $part->isMultipart;
    my @active = $part->parts('ACTIVE');
    @active==1 ? $active[0] : $part;
}

sub removeEmptyMultiparts($@)
{   my ($self, $part) = @_;
    $part->isMultipart && $part->body->parts==0 ? undef : $part;
}

sub flattenEmptyMultiparts($@)
{   my ($self, $part) = @_;

    $part->isMultipart && $part->parts('ACTIVE')==0
        or return $part;

    my $body     = $part->body;
    my $preamble = $body->preamble || Mail::Message::Body::Lines->new(data=>'');
    my $epilogue = $body->epilogue;
    my $newbody  = $preamble->concatenate($preamble, <<NO_PARTS, $epilogue);
  * PLEASE NOTE:
  * This multipart did not contain any parts (anymore)
  * and was therefore flattened.

NO_PARTS

    my $rebuild  = Mail::Message::Part->new
      ( head      => $part->head->clone
      , container => undef
      );
    $rebuild->body($newbody);
    $rebuild;
}

sub removeEmptyBodies($@)
{   my ($self, $part) = @_;
    $part->body->lines==0 ? undef : $part;
}

sub descendMultiparts($@)
{   my ($self, $part, %args) = @_;
    return $part unless $part->isMultipart;

    my $body    = $part->body;
    my $changed = 0;
    my @newparts;

    foreach my $part ($body->parts)
    {   my $new = $self->recursiveRebuildPart($part, %args);
        if(!defined $new)  { $changed++ }
	elsif($new==$part) { push @newparts, $part }
	else               { push @newparts, $new; $changed++ }
    }

    $changed or return $part;

    my $newbody = ref($body)->new
      ( based_on  => $body
      , parts     => \@newparts
      );

    my $rebuild = ref($part)->new
      ( head      => $part->head->clone
      , container => undef
      );

    $rebuild->body($newbody);   # update Content-* lines
    $rebuild;
 }

sub descendNested($@)
{   my ($self, $part, %args) = @_;
    $part->isNested or return $part;

    my $body      = $part->body;
    my $srcnested = $body->nested;
    my $newnested = $self->recursiveRebuildPart($srcnested, %args);

    defined $newnested or return undef;
    return $part if $newnested==$srcnested;

    # Changes in the encapsulated message
    my $newbody = ref($body)->new(based_on => $body, nested => $newnested);
    my $rebuild = ref($part)->new(head => $part->head->clone
      , container => undef);

    $rebuild->body($newbody);
    $rebuild;
}

sub removeDeletedParts($@)
{   my ($self, $part) = @_;
    $part->isDeleted ? undef : $part;
}

sub replaceDeletedParts($@)
{   my ($self, $part) = @_;

    ($part->isNested && $part->body->nested->isDeleted) || $part->isDeleted
        or return $part;

    my $structure = '';
    my $output    = Mail::Box::FastScalar->new(\$structure, '  ');
    $part->printStructure($output);

    my $dispfn   = $part->body->dispositionFilename || '';
    Mail::Message::Part->build
      ( data => "Removed content:\n\n$structure\n$dispfn"
      );
}

#------------------------------------------
# The more complex rules

sub removeHtmlAlternativeToText($@)
{   my ($self, $part, %args) = @_;
    $part->body->mimeType eq 'text/html'
        or return $part;

    my $container = $part->container;

    return $part
        unless defined $container
            && $container->mimeType eq 'multipart/alternative';

    # The HTML $part will be nulled when a plain text part is found
    foreach my $subpart ($container->parts)
    {   return undef if $subpart->body->mimeType eq 'text/plain';
    }

    $part;
}

sub removeExtraAlternativeText($@)
{   my ($self, $part, %args) = @_;

    my $container = $part->container;
    $container && $container->mimeType eq 'multipart/alternative'
        or return $part;

    # The last part is the preferred part (as per RFC2046)
    my $last = ($container->parts)[-1];
    $last && $part==$last ? $part : undef;
}

my $has_hft;
sub textAlternativeForHtml($@)
{   my ($self, $part, %args) = @_;

    my $hft = 'Mail::Message::Convert::HtmlFormatText';
    unless(defined $has_hft)
    {   eval "require Mail::Message::Convert::HtmlFormatText";
        $has_hft = $hft->can('format');
    }

    return $part
        unless $has_hft && $part->body->mimeType eq 'text/html';

    my $container = $part->container;
    my $in_alt    = defined $container
                    && $container->mimeType eq 'multipart/alternative';

    return $part
        if $in_alt
        && first { $_->body->mimeType eq 'text/plain' } $container->parts;


    # Create the plain part

    my $html_body  = $part->body;
    my $plain_body = $hft->new->format($html_body);

    my $plain_part = Mail::Message::Part->new(container => undef);
    $plain_part->body($plain_body);

    return $container->attach($plain_part)
       if $in_alt;

    # Recreate the html part to loose some header lines

    my $html_part = Mail::Message::Part->new(container => undef);
    $html_part->body($html_body);

    # Create the new part, with the headers of the html part

    my $mp = Mail::Message::Body::Multipart->new
     ( mime_type => 'multipart/alternative'
     , parts     => [ $plain_part, $html_part ]
     );

    my $newpart  = ref($part)->new
     ( head      => $part->head->clone   # Subject field, and such
     , container => undef
     );
    $newpart->body($mp);
    $newpart;
}

#------------------------------------------

=section Internals

=method recursiveRebuildPart $part, %options

=requires rules ARRAY-OF-RULES

Rules are method names which can be called on messages and message parts
objects.  The ARRAY can also list code references which can be called.
In any case, each rule will be called the same way:

 $code->(MESSAGE, PART)

The return can be C<undef> or any complex construct based on a
M<Mail::Message::Part> or coerceable into such a part.  For each part,
all rules are called in sequence.  When a rule returns a changed object,
the rules will start all over again, however C<undef> will immediately
stop it.

=cut

sub recursiveRebuildPart($@)
{   my ($self, $part, %args) = @_;

  RULES:
    foreach my $rule (@{$args{rules}})
    {   my $rebuild = $self->$rule($part, %args)
            or return undef;

        if($part != $rebuild)
        {   $part = $rebuild;
            redo RULES;
        }
    }

    $part;
}

#------------------------------------------

=chapter DETAILS

=section Rebuilding a message

Modifying an existing message is a complicated job.  Not only do you need
to know what you are willing to change, but you have to take care about
multiparts (possibly nested in multiple levels), rfc822 encapsulated
messages, header field consistency, and so on.  The M<rebuild()> method
let you focus on the task, and takes care of the rest.

The M<rebuild()> method uses rules to transform the one message into an
other.  If one or more of the rules apply, a new message will be returned.
A simple numeric comparison tells whether the message has changed.  For
example

 print "No change"
    if $message == $message->rebuild;

Transformation is made with a set of rules.  Each rule performs only a
small step, which makes is easily configurable.  The rules are ordered,
and when one makes a change to the result, the result will be passed
to all the rules again until no rule makes a change on the part anymore.
A rule may also return C<undef> in which case the part will be removed
from the (resulting) message.

=subsection General rules

This sections describes the general configuration rules: all quite straight
forward transformations on the message structure.  The rules marked with (*)
are used by default.

=over 4

=item * descendMultiparts (*)
Apply the rules to the parts of (possibly nested) multiparts, not only to
the top-level message.

=item * descendNested (*)
Apply the rules to the C<message/rfc822> encapsulated message as well.

=item * flattenEmptyMultiparts (*)
Multipart messages which do not have any parts left are replaced by
a single part which contains the preamble, epilogue and a brief
explanation.

=item * flattenMultiparts (*)
When a multipart contains only one part, that part will take the place of
the multipart: the removal of a level of nesting.  This way, the preamble
and epilogue of the multipart (which do not have a meaning, officially)
are lost.

=item * flattenNesting
Remove the C<message/rfc822> encapsulation.  Only the content related
lines of the encapsulated body are preserved one level higher.  Other
information will be lost, which is often not too bad.

=item * removeDeletedParts
All parts which are flagged for deletion are removed from the message
without leaving a trace.  If a nested message is encountered which has
its encapsulated content flagged for deletion, it will be removed as
a whole.

=item * removeEmptyMultiparts
Multipart messages which do not have any parts left are removed.  The
information in preamble and epiloge is lost.

=item * removeEmptyBodies
Simple message bodies which do not contain any lines of content are
removed.  This will loose the information which is stored in the
headers of these bodies.

=item * replaceDeletedParts (*)
All parts of the message which are flagged for deletion are replace
by a message which says that the part is deleted.

=back

You can specify a selection of these rules with M<rebuild(rules)> and
M<rebuild(extra_rules)>.

=subsection Conversion rules

This section describes the rules which try to be smart with the
content.  Please contribute with ideas and implementations.

=over 4

=item * removeHtmlAlternativeToText
When a multipart alternative is encountered, which contains both a
plain text and an html part, then the html part is deleted.
Especially useful in combination with the C<flattenMultiparts> rule.

=item * textAlternativeForHtml
Any C<text/html> part which is not accompanied by an alternative
plain text part will have one added.  You must have a working
M<Mail::Message::Convert::HtmlFormatText>, which means that
M<HTML::TreeBuilder> and M<HTML::FormatText>  must be installed on
your system.

=item * removeExtraAlternativeText
[2.110] When a multipart alternative is encountered, deletes all its parts
except for the last part (the preferred part in accordance
with RFC2046). In practice, this normally results in the alternative
plain text part being deleted of an html message. Useful in combination
with the C<flattenMultiparts> rule.
=back

=subsection Adding your own rules

If you have designed your own rule, please consider contributing this
to Mail::Box; it may be useful for other people as well.

Each rule is called

 my $new = $code->($message, $part, %options)

where the C<%options> are defined by the C<rebuild()> method internals. At
least the C<rules> option is passed, which is a full expansion of all
the rules which will be applied.

Your subroutine shall return C<$part> if no changes are needed,
C<undef> if the part should be removed, and any newly constructed
C<Mail::Message::Part> when a change is required.  It is easiest to
start looking at the source code of this package, and copy from a
comparible routine.

When you have your own routine, you simply call:

 my $rebuild_message = $message->rebuild
  ( extra_rules => [ \&my_own_rule, 'other_rule' ] );

=cut


1;
