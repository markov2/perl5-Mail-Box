#!/usr/bin/perl
#
# Test the creation of reply subjects
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Construct;
use Tools;

BEGIN {plan tests => 21}

ok(Mail::Message->replySubject('subject') eq 'Re: subject');
ok(Mail::Message->replySubject('Re: subject') eq 'Re[2]: subject');
ok(Mail::Message->replySubject('Re[1]: subject') eq 'Re[2]: subject');
ok(Mail::Message->replySubject('Re[2]: subject') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re: Re: subject') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re: Re[2]: subject') eq 'Re[4]: subject');
ok(Mail::Message->replySubject('Re Re: subject') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re,Re: subject') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re Re[2]: subject') eq 'Re[4]: subject');
ok(Mail::Message->replySubject('subject (Re)') eq 'Re[2]: subject');
ok(Mail::Message->replySubject('subject (Re) (Re)') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re: subject (Re)') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('subject (Forw)') eq 'Re[2]: subject');
ok(Mail::Message->replySubject('subject (Re) (Forw)') eq 'Re[3]: subject');
ok(Mail::Message->replySubject('Re: subject (Forw)') eq 'Re[3]: subject');

ok(Mail::Message->replySubject('subject: sub2') eq 'Re: subject: sub2');
ok(Mail::Message->replySubject('Re: subject: sub2') eq 'Re[2]: subject: sub2');
ok(Mail::Message->replySubject('subject : sub2') eq 'Re: subject : sub2');
ok(Mail::Message->replySubject('Re: subject : sub2 (Forw)')
   eq 'Re[3]: subject : sub2');
ok(Mail::Message->replySubject('') eq 'Re: your mail');
ok(Mail::Message->replySubject(undef) eq 'Re: your mail');
