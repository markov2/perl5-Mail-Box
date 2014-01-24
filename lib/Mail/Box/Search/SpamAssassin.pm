
package Mail::Box::Search::SpamAssassin;
use base 'Mail::Box::Search';

use strict;
use warnings;

use Mail::SpamAssassin;
use Mail::Message::Wrapper::SpamAssassin;

#-------------------------------------------

=chapter NAME

Mail::Box::Search::SpamAssassin - select spam messages with Mail::SpamAssassin

=chapter SYNOPSIS

 use Mail::Box::Manager;
 my $mgr    = Mail::Box::Manager->new;
 my $folder = $mgr->open('Inbox');

 my $spam = Mail::Box::Search::SpamAssassin->new;
 if($spam->search($message)) {...}

 my @msgs   = $filter->search($folder);
 foreach my $msg ($folder->messages)
 {   $msg->delete if $msg->label('spam');
 }

 my $spam2 = Mail::Box::Search::SpamAssassin
               ->new(deliver => 'DELETE');
 $spam2->search($folder);
 $mgr->moveMessages($spamfolder, $folder->messages('spam'));

=chapter DESCRIPTION

I<Spam> means "unsollicited e-mail", and is as name derived from a
Monty Python scatch.  Although Monty Python is fun, spam is a pain:
it needlessly spoils minutes of time from most people: telephone
bills, overful mailboxes which block honest e-mail, and accidentally
removal of honest e-mail which looks like spam.  Spam is the pest
of Internet.

Happily, Mail::Box can be used as spam filter, in combination with
the useful Mail::SpamAssassin module (which must be installed separately).
Each message which is searched is wrapped in a
M<Mail::Message::Wrapper::SpamAssassin> object.

The spam-assassin module version 2 is not really well adapted for
M<Mail::Message> objects, which will make this search even slower than
spam-detection already is.

=chapter METHODS

=c_method new %options

Create a spam filter.  Internally, a M<Mail::SpamAssassin> object is
maintained.

=default in    C<'MESSAGE'>

Only the whole message can be searched; this is a limitation of
the M<Mail::SpamAssassin> module.

=option  label STRING|undef
=default label c<'spam'>

Mark all selected message with the specified STRING.  If this
option is explicitly set to C<undef>, the label will not be set.

=option  rewrite_mail BOOLEAN
=default rewrite_mail <true>

Add lines to the message header describing the results of the spam
scan. See M<Mail::SpamAssassin::PerMsgStatus::rewrite_mail()>.

=option  spam_assassin OBJECT
=default spam_assassin undef

Provide a Mail::SpamAssassin object to be used for searching spam.  If
none is specified, one is created internally.  The object can be
retrieved with assassinator().

=option  sa_options     HASH
=default sa_options     C<{ }>

Options to create the internal M<Mail::SpamAssassin> object; see its
manual page for the available options.  Other setting may be provided
via SpamAssassins configuration file mechanism, which is explained in
L<Mail::SpamAssassin::Conf>.

=examples

 my $filter = Mail::Box::Search::SpamAssassin
               ->new( found => 'DELETE' );

=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{in}  ||= 'MESSAGE';
    $args->{label} = 'spam' unless exists $args->{label};

    $self->SUPER::init($args);

    $self->{MBSS_rewrite_mail}
       = defined $args->{rewrite_mail} ? $args->{rewrite_mail} : 1;

    $self->{MBSS_sa}
       = defined $args->{spamassassin} ? $args->{spamassassin}
       : Mail::SpamAssassin->new($args->{sa_options} || {});

    $self;
}

#-------------------------------------------

=section Searching

=method assassinator

Returns the internally maintained assassinator object.  You may want
to reach this object for complex configuration.

=cut

sub assassinator() { shift->{MBSS_sa} }

#-------------------------------------------

sub searchPart($)
{   my ($self, $message) = @_;

    my @details = (message => $message);
   
    my $sa      = Mail::Message::Wrapper::SpamAssassin->new($message)
        or return;

    my $status  = $self->assassinator->check($sa);

    my $is_spam = $status->is_spam;
    $status->rewrite_mail if $self->{MBSS_rewrite_mail};

    if($is_spam)
    {   my $deliver = $self->{MBS_deliver};
        $deliver->( {@details, status => $status} ) if defined $deliver;
    }

    $is_spam;
}

#-------------------------------------------

sub inHead(@) {shift->notImplemented}

#-------------------------------------------

sub inBody(@) {shift->notImplemented}

#-------------------------------------------

1;
