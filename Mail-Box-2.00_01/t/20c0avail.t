#!/usr/bin/perl -w
#
# Check whether we can run the C parser (otherwise it is useless to
# perform this set of tests.
#

use Test;
use strict;
use lib qw(. t /home/markov/MailBox2/fake);

BEGIN
{   eval 'require Inline::C';
    if($@)
    {   warn <<'NO_INLINE_C';
    Inline::C is not installed.
 ** if you want performance, then you can better install
 ** the Inline::C module.  YOU DO NEED to reinstall this
 ** module thereafter.
NO_INLINE_C

        plan tests => 0;
        exit 0;
    }
    plan tests => 1;

    eval 'require Mail::Box::Parser::C';
    if($@)
    {   warn "    Parser code doesn't compile:\n$@";
    }
    ok(not $@);
}
