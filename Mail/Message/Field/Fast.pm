use strict;
use warnings;

package Mail::Message::Field::Fast;
use base 'Mail::Message::Field';

use Carp;

=head1 NAME

Mail::Message::Field::Fast - one line of a message header

=head1 SYNOPSIS

 See Mail::Message::Field

=head1 DESCRIPTION

This is the faster, but less flexible
implementation of a header field.  The data is stored in an array,
and some hacks are made to speeds things up.  Be gentle with me, and
consider that each message contains many of these lines, so speed
is very important here.

=head1 METHODS

=cut

#------------------------------------------
#
# The DATA is stored as:   [ NAME, FOLDED-BODY ]
# The body is kept in a folded fashion, where each line starts with
# a single blank.

=head2 Initiation

=cut

#------------------------------------------

=c_method new DATA

The constructor of this object does not follow the usual practise within
the Mail::Box suite: it does not use the constructor Mail::Reporter::new().
Therefor it has no logging or tracing facilities.

The method can be used in one of the following ways:

=over 4

=item * B<new> LINE

=item * B<new> NAME, (BODY|OBJECTS), [ATTRIBUTES]

=back

Create a new header field object.  Specify the whole LINE at once, and
it will be split-up for you.  I case you already have the parts of the
header line, you may specify them separately as NAME and BODY.

In case you specify a single OBJECT, or a reference to an array of OBJECTS,
these objects are processed to become suitable to fill a field, usually
by simple strification.  When you specify one or more Mail::Address objects,
these are transformed into a string using their C<format> method.
You may also add one Mail::Message::Field, whose body is taken.  In case of
 an array, the elements are joined into one string with a comma.

ATTRIBUTES can be exactly one string which may contain multiple attributes
at once, quoted and formatted as required in RFC2822.  As alternative,
list of key-value pairs can be used.  In this case, the values will get
quoted if needed and everything formatted as the protocol demands.

=examples

 my $mime = Mail::Message::Field->new(
     'Content-Type: text/plain; charset=US-ASCII');

 my $mime = Mail::Message::Field->new(
     'Content-Type' => 'text/plain; charset=US-ASCII');

 my $mime = Mail::Message::Field->new(
     'Content-Type' => 'text/plain', 'charset=US-ASCII');

 my $mime = Mail::Message::Field->new(
     'Content-Type' => 'text/plain', charset => 'US-ASCII');

 my $mime = Mail::Message::Field->new(
     To => Mail::Address->new('my name', 'me@example.com');

 my $mime = Mail::Message::Field->new(
     Cc => [ Mail::Address->new('your name', 'you@example.com')
           , Mail::Address->new('his name', 'he@example.com')
           ]);

But in practice, you can simply call

 my $head = Mail::Message::Head->new;
 $head->add('Content-Type' => 'text/plain', charset => 'US-ASCII');

which implicitly calls this constructor (when needed).  You can specify
the same things for add() as this C<new> accepts.

=default log   <disabled>
=default trace <disabled>

=cut

sub new($;$@)
{   my $class = shift;

    my ($name, $body) = $class->consume(@_==1 ? (shift) : (shift, shift));
    return () unless defined $body;

    my $self = bless [$name, $body], $class;

    # Attributes
    $self->comment(shift)             if @_==1;   # one attribute line
    $self->attribute(shift, shift) while @_ > 1;  # attribute pairs

    $self;
}

#------------------------------------------

=head2 The Field

=cut

#------------------------------------------

sub clone()
{   my $self = shift;
    bless [ @$self ], ref $self;
}

#------------------------------------------

sub length()
{   my $self = shift;
    length($self->[0]) + 1 + length($self->[1]);
}

#------------------------------------------

=head2 Access to the Field

=cut

#------------------------------------------

sub name() { lc shift->[0] }

#------------------------------------------

sub Name() { shift->[0] }

#------------------------------------------

sub folded()
{   my $self = shift;
    return $self->[0].':'.$self->[1]
        unless wantarray;

    my @lines = $self->foldedBody;
    my $first = $self->[0]. ':'. shift @lines;
    ($first, @lines);
}

#------------------------------------------

sub unfoldedBody($;@)
{   my $self = shift;

    $self->[1] = $self->fold($self->[0], @_)
       if @_;

    $self->unfold($self->[1]);
}

#------------------------------------------

sub foldedBody($)
{   my ($self, $body) = @_;
    if(@_==2) { $self->[1] = $body }
    else      { $body = $self->[1] }
     
    wantarray ? (split m/^/, $body) : $body;
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

# For performance only

sub print(;$)
{   my $self = shift;
    (shift || select)->print($self->[0].':'.$self->[1]);
}

#------------------------------------------

1;
