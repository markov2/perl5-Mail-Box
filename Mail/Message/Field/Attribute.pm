use strict;
use warnings;

package Mail::Message::Field::Attribute;

use Mail::Reporter;
use 5.007003;
use Encode ();

use Carp;

=head1 NAME

Mail::Message::Field::Attribute - one attribute of a full field

=head1 SYNOPSIS

 my $field    = $msg->head->get('Content-Disposition') or return;
 my $full     = $field->study;   # full understanding in unicode
 my $filename = $full->attribute(filename)             or return;

 print ref $filename;     # this class name
 print $filename;         # the attributes content in utf-8
 print $filename->value;  # same
 print $filename->string; # print string as was found in the file
 $filename->print(\*OUT); # print as was found in the file

=head1 DESCRIPTION

Attributes within MIME fields can be quite complex, and therefore be slow
and consumes a lot of memory.  The Mail::Message::Field::Fast and
Mail::Message::Field::Flex simplify them the attributes a lot, which
may result in erroneous behavior in rare cases.  With the increase of
non-western languages on Internet, the need for the complex headers
becomes more and more in demand.

A Mail::Message::Field::Attribute can be found in any structured
Mail::Message::Field::Full header field.

=head1 METHODS

=cut

#------------------------------------------

=head2 Initiation

=cut

#------------------------------------------

=method new (NAME, [VALUE] | STRING), OPTIONS

Create a new attribute NAME with the optional VALUE.  If no VALUE is specified,
the first argument of this method is inspected for an equals sign C<'='>.
If that character is present, the argument is taken as STRING, containing
a preformatted attribute which is processed.  Otherwise, the argument is
taken as name without VALUE: set the value later with value().

Whether encoding takes place
depends on the OPTIONS and the existence of non-ascii characters in the VALUE.
The NAME can only contain ascii characters, hence is never encoded.

To speed things up, attributes are not derived from the Mail::Reporter
base-class.

=option  charset STRING
=default charset 'us-ascii'

The VALUE is translated from utf-8 (Perl internal) to this character set,
and the resulting string is encoded if required.  C<us-ascii> is the normal
encoding for e-mail.  Valid character sets can be found with 
Encode::encodings(':all').

=option  language STRING
=default language C<undef>

RFC2231 adds the possiblity to specify a language with the field.  When no
language is specified, none is included in the encoding.  Valid language names
are defined by RFC2130.  This module has only limited support for this feature.

=option  use_continuations BOOLEAN
=default use_continuations 1

Continuations are used to break-up long parameters into pieces which are no
longer than 76 characters. Encodings are specified in RFC2231, but not supported
by some Mail User Agents.

=examples

 my $fn    = Mail::Message::Field::Attribute->new(filename => 'xyz');

 my $fattr = 'Mail::Message::Field::Attribute';  # abbrev
 my $fn    = $fattr->new
     ( filename => "Re\xC7u"
     , charset  => 'iso-8859-15'
     , language => 'nl-BE'
     );
 print $fn;   # print  filename*=iso-8859-15'nl-BE'Re%C7u

=cut

sub new($$@)
{   my ($class, $attr) = (shift, shift);
    my $value = @_ % 1 == 1 ? shift : undef;
    my %args  = @_;

    my $name  = $attr =~ m/^(.*?)(?:\*\d+)?\*?\=/ ? $1 : $attr;
    Mail::Reporter->log(WARNING => "Illegal character in parameter name '$name'\n")
        if $name !~ m/^[!#-'*+\-.0-9A-Z^-~]+$/;

    my $self  = bless
     { MMFF_name    => $name
     , MMFF_usecont =>
          (defined $args{use_continuations} ? $args{use_continuations} : 1)
     }, $class;

    $self->{MMFF_charset}  = $args{charset}  if defined $args{charset};
    $self->{MMFF_language} = $args{language} if defined $args{language};

    $self->value($value)       if defined $value;
    $self->addComponent($attr) unless $attr eq $name;

    $self;
}

#------------------------------------------

=method name

Returns the name of this attribute.

=cut

sub name() { shift->{MMFF_name} }

#------------------------------------------

=method value [STRING]

Returns the value of this parameter, optionally after setting it first.

=cut

sub value(;$)
{   my $self = shift;
    if(@_)
    {   delete $self->{MMFF_cont};
        return $self->{MMFF_value} = shift;
    }
      
    exists $self->{MMFF_value} ? $self->{MMFF_value} : $self->decode;
}

#------------------------------------------

=method addComponent STRING

A component is a parameter as defined by RFC2045, optionally using
encoding or continuations as defined by RFC2231.  Components of an
attribute are found when a field is being parsed.  The RFCs are
very strict on valid characters, but we cannot be: you have to accept
what is coming in if you can.

=example

 my $param = Mail::Message::Field::Attribute->new('Content-Type');
 $param->addComponent("filename*=iso10646'nl-BE'%Re\47u");

=cut

sub addComponent($)
{   my ($self, $component) = @_;
    delete $self->{MMFF_value};

    my ($name, $value) = split /\=/, $component, 2;
    if( substr($name, -1) eq '*' && $value =~ m/^([^']*)\'([^']*)\'/ )
    {   $self->{MMFF_charset}  = length $1 ? $1 : undef;
        $self->{MMFF_language} = length $2 ? $2 : undef;
    }

    if( $name =~ m/\*([0-9]+)\*?$/ )
         { $self->{MMFF_cont}[$1] = $component }
    else { $self->{MMFF_cont}     = [ $component ] }

    $component;
}

#------------------------------------------

=method charset

Returns the character set which is used for this parameter.  If any component
is added which contains character set information, this is directly
available.  Be warned that a character-set is case insensitive.

=cut

sub charset() { shift->{MMFF_charset} }

#------------------------------------------

=method language

Returns the language which is defined in the argument.  If no language is
defined C<undef> is returned, which should be interpreted as "ANY"

=cut

sub language() { shift->{MMFF_language} }

#------------------------------------------

=method string

Returns the parameter as reference to an array of lines.  When only one line
is returned, it may be short enough to fit on the same line with other components
of the header field.

=cut

sub string()
{   my $self = shift;
    my $cont = $self->{MMFF_cont} || $self->encode;
    return @$cont if wantarray;
    return [] unless @$cont;

    local $" = "; ";
    "; @$cont";
}

#------------------------------------------

=head2 Reading and Writing [internals]

=cut

#------------------------------------------

=method encode

=cut

sub encode()
{   my $self  = shift;
    my $value = $self->{MMFF_value};

    my @lines;
    my ($pre, $encoded);

    my $charset  = $self->{MMFF_charset}  || '';
    my $lang     = $self->{MMFF_language} || '';
    my $name     = $self->{MMFF_name};
    my $cont     = $self->{MMFF_usecont};

    if($charset || $lang)
    {   $pre     = "$name*0*=$charset'$lang'";
        $value   = Encode::encode($charset, $value, 0);
        $encoded = 1;
    }
    elsif(grep m/[^\x20-\x7E]/, $value)
    {   $pre     = "$name*0*=''";
        $encoded = 1;
    }
    else
    {   $pre     = "$name*0=";
        $value   =~ s/"/\\"/g;
        $encoded = 0;
    }

    if($encoded)
    {   # Use encoding
        my @c    = split //, $value;
        while(@c)
        {   my $c = shift @c;
            $c = '%'. sprintf "%02X", ord $c
               unless $c =~ m/[a-zA-Z0-9]/;

            if($cont && length($pre) + length($c)> 76)
            {   push @lines, $pre;
                $pre = $name . '*' . @lines . '*=' . $c;
            }
            else { $pre .= $c }
        }
        push @lines, $pre;
    }
    elsif($cont)
    {   # Simple string, but with continuations
        while(1)
        {   push @lines, $pre . '"' . substr($value, 0, 75-length($pre), '') . '"';
            last unless length $value;
            $pre = $name . '*' . @lines . '=';
        }
            
    }
    else
    {   # Single string only
        push @lines, $pre . $value;
    }

    $lines[0] =~ s/\*0// if @lines==1;
    $self->{MMFF_cont} = \@lines;
}

#------------------------------------------

=method decode

Translate all known continuations into a value.  The produced value is
returned and may be utf-8 encoded or a plain string.

=cut

sub decode()
{   my $self  = shift;
    my $value = '';

    foreach my $cont (  @{$self->{MMFF_cont}} )
    {   unless(defined $cont)
        {   $value .= "[continuation missing]";
            next;
        }

        (my $name, local $_) = split /\=/, $cont, 2;

        if(substr($name, -1) eq '*')
        {   s/^[^']*\'[^']*\'//;
            s/\%([a-fA-F0-9]{2})/chr hex $1/ge;
        }
        elsif( s/^\"(.*)\"$/$1/ ) { s/\\\"/"/g }
        elsif( s/^\'(.*)\'$/$1/ ) { s/\\\'/'/g }

        $value .= $_;
    }

    my $charset = $self->{MMFF_charset};
    $value = Encode::decode($charset, $value, 0) if $charset;

    $self->{MMFF_value} = $value;
}

#------------------------------------------

=method mergeComponent ATTRIBUTE

Merge the components from the specified attribute in this attribute.  This is
needed when components of the same attribute are created separately.  Merging
is required by the field parsing.

=cut

sub mergeComponent($)
{   my ($self, $comp) = @_;
    my $cont  = $self->{MMFF_cont}
       or croak "Too late to merge: value already changed.";

    defined $_ && $self->addComponent($_)
        foreach @{$comp->{MMFF_cont}};

    $self;
}

#------------------------------------------

1;
