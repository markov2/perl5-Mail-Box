use strict;
use warnings;

# Parse mail-boxes with plain Perl.  See Mail::Box::Parser
#
# Copyright (c) 2001 Mark Overmeer. All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

package Mail::Box::Parser::Perl;
use base 'Mail::Box::Parser';

our $VERSION = '2.00_01';

sub init(@)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
}

