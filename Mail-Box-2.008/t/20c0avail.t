#!/usr/bin/perl
#
# Check whether we can run the C parser (otherwise it is useless to
# perform this set of tests.
#

use Test;
use strict;
use warnings;

use lib qw(. t /home/markov/MailBox2/fake);
use Tools;

BEGIN
{   warn <<'DISABLED';

** The C based parser is currently disabled because it is not
** stable: there must be a bug in Mail::Box::Parser::C or
** Inline::C.  More testing is required.
DISABLED

# To perform tests, the next two code lines must be commented out, and
# one line in Mail/Box/Parser/C.pm must be added to break the module.
    plan tests => 0;
    exit 0;
}

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

    warn "   * Parser in C status ALPHA\n";

    ok(not $@);
}
