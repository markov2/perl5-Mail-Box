#!/usr/bin/perl -w
#
# Test the creation of reply subjects
#

use Test;
use strict;

use lib qw(. t /home/markov/MailBox2/fake);

use Mail::Message::Construct;
use Tools;

BEGIN {plan tests => 19}

*replySubject = *Mail::Message::replySubject;

ok(replySubject('subject') eq 'Re: subject');
ok(replySubject('Re: subject') eq 'Re[2]: subject');
ok(replySubject('Re[1]: subject') eq 'Re[2]: subject');
ok(replySubject('Re[2]: subject') eq 'Re[3]: subject');
ok(replySubject('Re: Re: subject') eq 'Re[3]: subject');
ok(replySubject('Re: Re[2]: subject') eq 'Re[4]: subject');
ok(replySubject('Re Re: subject') eq 'Re[3]: subject');
ok(replySubject('Re,Re: subject') eq 'Re[3]: subject');
ok(replySubject('Re Re[2]: subject') eq 'Re[4]: subject');
ok(replySubject('subject (Re)') eq 'Re[2]: subject');
ok(replySubject('subject (Re) (Re)') eq 'Re[3]: subject');
ok(replySubject('Re: subject (Re)') eq 'Re[3]: subject');
ok(replySubject('subject (Forw)') eq 'Re[2]: subject');
ok(replySubject('subject (Re) (Forw)') eq 'Re[3]: subject');
ok(replySubject('Re: subject (Forw)') eq 'Re[3]: subject');

ok(replySubject('subject: sub2') eq 'Re: subject: sub2');
ok(replySubject('Re: subject: sub2') eq 'Re[2]: subject: sub2');
ok(replySubject('subject : sub2') eq 'Re: subject : sub2');
ok(replySubject('Re: subject : sub2 (Forw)') eq 'Re[3]: subject : sub2');
