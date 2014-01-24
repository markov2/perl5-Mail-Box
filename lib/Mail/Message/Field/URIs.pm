use warnings;
use strict;

package Mail::Message::Field::URIs;
use base 'Mail::Message::Field::Structured';

use URI;

=chapter NAME

Mail::Message::Field::URIs - message header field with uris

=chapter SYNOPSIS

 my $f = Mail::Message::Field->new('List-Post' => 'http://x.org/');

 my $g = Mail::Message::Field->new('List-Post');
 $g->addURI('http://x.org');

 my $uri = URI->new(...);
 $g->addURI($uri);

 my @uris = $g->URIs;

=chapter DESCRIPTION

More recent RFCs prefer uri field notation over the various differentiated
syntaxes.  Especially the mailing-list RFCs use these fields all the
time.  This class can maintain these fields.

=chapter METHODS

=cut

=section Constructors

=c_method new $data

=default attributes <ignored>

=examples

 my $mmfu = 'Mail::Message::Field::URIs;
 my $f = $mmfu->new('List-Post' => 'mailto:x@y.com');
 my $f = $mmfu->new('List-Post' => '<mailto:x@y.com>');
 my $f = $mmfu->new('List-Post: <mailto:x@y.com>');
 my $f = $mmfu->new('List-Post' => [ $uri, 'http://x.org' ]);

=cut

sub init($)
{   my ($self, $args) = @_;

    my ($body, @body);
    if($body = delete $args->{body})
    {   @body = ref $body eq 'ARRAY' ? @$body : ($body);
        return () unless @body;
    }

    $self->{MMFU_uris} = [];

    if(@body > 1 || ref $body[0])
    {   $self->addURI($_) foreach @body;
    }
    elsif(defined $body)
    {   $body = "<$body>\n" unless index($body, '<') >= 0;
        $args->{body} = $body;
    }

    $self->SUPER::init($args);
}

sub parse($)
{   my ($self, $string) = @_;
    my @raw = $string =~ m/\<([^>]+)\>/g;  # simply ignore all but <>
    $self->addURI($_) foreach @raw;
    $self;
}

sub produceBody()
{  my @uris = sort map { $_->as_string } shift->URIs;
   local $" = '>, <';
   @uris ? "<@uris>" : undef;
}

#------------------------------------------

=section Access to the content

=method addURI $uri
Add an $uri to the field.  The $uri can be specified as M<URI> object
or as string which will be turned into an $uri object.  The added
$uri is returned.

=examples adding an URI to an URI field
 my $f   = Mail::Message::Field::URI->new('List-Post');

 my $uri = URI->new("http://x.org");
 $f->addURI($uri);

 $f->addURI("http://y.org");  # simpler
 $f->addURI("//y.org", "http");
=cut

sub addURI(@)
{   my $self  = shift;
    my $uri   = ref $_[0] ? shift : URI->new(@_);
    push @{$self->{MMFU_uris}}, $uri->canonical if defined $uri;
    $uri;
}

#------------------------------------------

=method URIs
Returns a list with all URIs defined by the field.  Mind the lower-case
's' at the enc of the name.

=example
 my @uris = $field->URIs;
=cut

sub URIs() { @{shift->{MMFU_uris}} }

=method addAttribute ...
Attributes are not supported for URI fields.

=error No attributes for URI fields.
Is is not possible to add attributes to URI fields: it is not permitted
by the RFCs.
=cut

sub addAttribute($;@)
{   my $self = shift;
    $self->log(ERROR => 'No attributes for URI fields.');
    $self;
}

#------------------------------------------

=section Error handling
=cut

1;
