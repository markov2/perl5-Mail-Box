
use strict;
use warnings;

package Mail::Message::Replace::MailInternet;
use base 'Mail::Message';

use Mail::Box::FastScalar;
use Mail::Box::Parser::Perl;
use Mail::Message::Body::Lines;

use File::Spec;

=chapter NAME

Mail::Message::Replace::MailInternet - fake Mail::Internet

=chapter SYNOPSIS

 !!! BETA !!!

 # change
 use Mail::Internet;
 # into
 use Mail::Message::Replace::MailInternet;
 # in existing code, and the code should still work, but
 # with the Mail::Message features.
 
=chapter DESCRIPTION

This module is a wrapper around a M<Mail::Message>, which simulates
a L<Mail::Internet> object.  The name-space of that module is hijacked
and many methods are added.

Most methods will work without any change, but you may need to have
a look at your M<smtpsend()> and M<send()> calls.

=chapter OVERLOADED

=chapter METHODS

=section Constructors

=c_method new [$arg], [%options]

=default head_type M<Mail::Message::Replace::MailHeader>

=option  Header OBJECT
=default Header C<undef>
The L<Mail::Header> object, which is passed here, is a fake one as well...
It is translated into a M<new(head)>.  If not given, the header will be
parsed from the $arg.

=option  Body ARRAY-OF-LINES
=default Body C<undef>
Array of C<"\n"> terminated lines.  If not specified, the lines will be
read from $arg.

=option  Modify BOOLEAN
=default Modify 0
Whether to re-fold all the incoming fields.
Passed to M<Mail::Message::Replace::MailHeader::new(Modify)>.

=option  MailFrom 'IGNORE'|'ERROR'|'COERCE'|'KEEP'
=default MailFrom C<'KEEP'>
What to do with leading "C<From >" lines in e-mail data.
Passed to M<Mail::Message::Replace::MailHeader::new(MailFrom)>.

=option  FoldLength INTEGER
=default FoldLength 79
Number of characters permitted on any refolded header line.
Passed to M<Mail::Message::Replace::MailHeader::new(FoldLength)>.

=example replace traditional Mail::Internet by this wrapper
  # was
  use Mail::Internet;
  my $mi = Mail::Internet->new(@options);

  # becomes
  use Mail::Message::Replace::MailInternet;
  my $mi = Mail::Internet->new(@options);

=error Mail::Internet does not support this kind of data
The ARGS data can only be a file handle or an ARRAY.  Other data types
are not supported (see M<read()> if you want to have more).

=cut

sub new(@)
{   my $class = shift;
    my $data  = @_ % 2 ? shift : undef;
    $class = __PACKAGE__ if $class eq 'Mail::Internet';
    $class->SUPER::new(@_, raw_data => $data);
}

sub init($)
{   my ($self, $args) = @_;
    $args->{head_type} ||= 'Mail::Message::Replace::MailHeader';
    $args->{head}      ||= $args->{Header};
    $args->{body}      ||= $args->{Body};

    defined $self->SUPER::init($args) or return;

    $self->{MI_wrap}      = $args->{FoldLength} || 79;
    $self->{MI_mail_from} = $args->{MailFrom};
    $self->{MI_modify}    = exists $args->{Modify} ? $args->{Modify} : 1;

    $self->processRawData($self->{raw_data}, !defined $args->{Header}
       , !defined $args->{Body}) if defined $self->{raw_data};

    $self;
}

sub processRawData($$$)
{   my ($self, $data, $get_head, $get_body) = @_;
    return $self unless $get_head || $get_body;
 
    my ($filename, $lines);
    if(ref $data eq 'ARRAY')
    {   $filename = 'array of lines';
        $lines    = $data;
    }
    elsif(ref $data eq 'GLOB')
    {   $filename = 'file (GLOB)';
        $lines    = [ <$data> ];
    }
    elsif(ref $data && $data->isa('IO::Handle'))
    {   $filename = 'file ('.ref($data).')';
        $lines    = [ $data->getlines ];
    }
    else
    {   $self->log(ERROR=> "Mail::Internet does not support this kind of data");
        return undef;
    }

    return unless @$lines;

    my $buffer = join '', @$lines;
    my $file   = Mail::Box::FastScalar->new(\$buffer);

    my $parser = Mail::Box::Parser::Perl->new
     ( filename  => $filename
     , file      => $file
     , trusted   => 1
     );

    my $head;
    if($get_head)
    {   my $from = substr($lines->[0], 0, 5) eq 'From ' ? shift @$lines : undef;

        my $head = $self->{MM_head_type}->new
          ( MailFrom   => $self->{MI_mail_from}
          , Modify => $self->{MI_modify}
          , FoldLength => $self->{MI_wrap}
          );
        $head->read($parser);
        $head->mail_from($from) if defined $from;
        $self->head($head);
    }
    else
    {   $head = $self->head;
    }

    $self->storeBody($self->readBody($parser, $head)) if $get_body;
    $self->addReport($parser);
    $parser->stop;
    $self;
}

=method dup
Duplicate the message.  The result will again be a L<Mail::Internet>
compatible object.
=cut

sub dup()
{   my $self = shift;
    ref($self)->coerce($self->clone);
}

=method empty
Remove all data from this object.  Very dangerous!
=cut

sub empty() { shift->DESTROY }

=section Attributes

=method MailFrom [STRING]
Your email address.
=cut

sub MailFrom(;$)
{   my $self = shift;
    @_ ? ($self->{MI_mail_from} = shift) : $self->{MU_mail_from};
}

=section Constructing a message

=ci_method read ARRAY|$fh, %options
Read header and body from the specified ARRAY or $fh.  When used as
object method, M<Mail::Message::read()> is called, to be MailBox compliant.
As class method, the Mail::Internet compatible read is called.  %options are
only available in the first case.

=cut

sub read($@)
{   my $thing = shift;

    return $thing->SUPER::read(@_)   # Mail::Message behavior
        unless ref $thing;

    # Mail::Header emulation
    my $data = shift;
    $thing->processRawData($data, 1, 1);
}

=method read_body ARRAY|$fh
Read only the message's body from the ARRAY or $fh.
=cut

sub read_body($)
{   my ($self, $data) = @_;
    $self->processRawData($data, 0, 1);
}

=method read_header ARRAY|$fh
Read only the message's header from the ARRAY or $fh
=cut

sub read_header($)
{   my ($self, $data) = @_;
    $self->processRawData($data, 1, 0);
}

=method extract ARRAY|$fh
Read header and body from an ARRAY or $fh
=cut

sub extract($)
{   my ($self, $data) = @_;
    $self->processRawData($data, 1, 1);
}

=method reply %options
BE WARNED: the main job for creating a reply is done by
M<Mail::Message::reply()>, which may produce a result which is compatible,
but may be different from L<Mail::Internet>'s version.

=option  header_template FILENAME|C<undef>
=default header_template C<$ENV{HOME}/.mailhdr>
Read the return header from the template file.  When this is explicitly
set to C<undef>, or the file does not exist, then a header will be created.

=option  Inline STRING
=default Inline E<gt>
Quotation STRING, which is translated into M<reply(quote)>.  The normal
default of C<quote> is "E<gt> ", in stead of "E<gt>".

=option  ReplyAll BOOLEAN
=default ReplyAll <false>
Reply to the group?  Translated into M<reply(group_reply)>, which has
as default the exact oposite of this option, being C<true>.

=option  Keep ARRAY-OF-NAMES
=default Keep []
Copy all header fields with the specified NAMES from the source to the
reply message.

=option  Exclude ARRAY-OF-NAMES
=default Exclude []
Remove the fields witht the specified names from the produced reply message.

=cut

sub reply(@)
{   my ($self, %args) = @_;

    my $reply_head = $self->{MM_head_type}->new;
    my $home       = $ENV{HOME} || File::Spec->curdir;
    my $headtemp   = File::Spec->catfile($home, '.mailhdr');

    if(open HEAD, '<:raw', $headtemp)
    {    my $parser = Mail::Box::Parser::Perl->new
           ( filename  => $headtemp
           , file      => \*HEAD
           , trusted   => 1
           );
         $reply_head->read($parser);
         $parser->close;
    }

    $args{quote}       ||= delete $args{Inline}   || '>';
    $args{group_reply} ||= delete $args{ReplyAll} || 0;
    my $keep             = delete $args{Keep}     || [];
    my $exclude          = delete $args{Exclude}  || [];

    my $reply = $self->SUPER::reply(%args);

    my $head  = $self->head;

    $reply_head->add($_->clone)
        foreach map { $head->get($_) } @$keep;

    $reply_head->reset($_) foreach @$exclude;

    ref($self)->coerce($reply);
}

=method add_signature [$filename]
Replaced by M<sign()>, but still usable. $filename is the file which
contains the signature, which defaults to C<$ENV{HOME}/.signature>.
=cut

sub add_signature(;$)
{   my $self     = shift;
    my $filename = shift
       || File::Spec->catfile($ENV{HOME} || File::Spec->curdir, '.signature');
    $self->sign(File => $filename);
}

=method sign %options
Add a signature (a few extra lines) to the message.

=option  File FILENAME
=default File C<undef>
Specifies a filename where the signature is in.

=option  Signature STRING|ARRAY-OF-LINES
=default Signature ''
The signature in memory.

=cut

sub sign(@)
{   my ($self, $args) = @_;
    my $sig;

    if(my $filename = delete $self->{File})
    {   $sig = Mail::Message::Body->new(file => $filename);
    }
    elsif(my $sig   = delete $self->{Signature})
    {   $sig = Mail::Message::Body->new(data => $sig);
    }

    return unless defined $sig;
 
    my $body = $self->decoded->stripSignature;
    my $set  = $body->concatenate($body, "-- \n", $sig);
    $self->body($set) if defined $set;
    $set;
}

=section The message
=method send $type, %options
Send via Mail Transfer Agents (MUA).  These will be handled by various
M<Mail::Transport::Send> extensions.  The C<test> $type is not supported.
=cut

sub send($@)
{   my ($self, $type, %args) = @_;
    $self->send(via => $type);
}

=method nntppost %options
Send an NNTP message (newsgroup message), which is equivalent to
M<Mail::Transport::NNTP> or M<Mail::Message::send()> with C<via 'nntp'>.

=option  Host HOSTNAME
=default Host <from Net::Config>

=option  Port INTEGER
=default Port 119

=option  Debug BOOLEAN
=default Debug <false>

=cut

sub nntppost(@)
{   my ($self, %args) = @_;
    $args{port}       ||= delete $args{Port};
    $args{nntp_debug} ||= delete $args{Debug};

    $self->send(via => 'nntp', %args);
}

=method print [$fh]
Prints the whole message to the specified $fh, which default to
STDOUT.  This calls M<Mail::Message::print()>.
=cut

=section The header

=method head [$head]
Returns the head of the message, or creates an empty one if none is
defined.  The $head argument, which sets the header, is not available
for L<Mail::Internet>, but is there to be compatible with the C<head>
method of M<Mail::Message>.

=cut

sub head(;$)
{  my $self = shift;
   return $self->SUPER::head(@_) if @_;
   $self->SUPER::head || $self->{MM_head_type}->new(message => $self);
}

=method header [ARRAY]
Optionally reads a header from the ARRAY, and then returns those fields
as array-ref nicely folded.
Implemented by M<Mail::Message::Replace::MailHeader::header()>
=cut

sub header(;$) { shift->head->header(@_) }

=method fold [$length]
Fold all the fields to a certain maximum $length.
Implemented by M<Mail::Message::Replace::MailHeader::fold()>
=cut

sub fold(;$) { shift->head->fold(@_) }

=method fold_length [[$tag], $length]
Set the maximum line $length.  $tag is ignored.
Implemented by M<Mail::Message::Replace::MailHeader::fold_length()>
=cut

sub fold_length(;$$) { shift->head->fold_length(@_) }

=method combine $tag, [$with]
Not implemented, because I see no use for it.
=cut

sub combine($;$) { shift->head->combine(@_) }

=method print_header $fh
Calls M<Mail::Message::Head::Complete::print()>.
=cut

sub print_header(@) { shift->head->print(@_) }

=method clean_header
Not to be used, replaced by M<header()>.
=cut

sub clean_header() { shift->header }

=method tidy_headers
No effect anymore (always performed).
=cut

sub tidy_headers() { }

=method add $lines
Add header lines, which simply calls C<Mail::Message::Head::add()> on
the header for each specified LINE. The last added LINE is returned.
=cut

sub add(@) { shift->head->add(@_) }

=method replace $tag, $line, [$index]
Adds LINES to the header, but removes fields with the same name if they
already exist.  Calls M<Mail::Message::Replace::MailHeader::replace()>

=cut

sub replace(@) { shift->head->replace(@_) }

=method get $name, [$index]
Get all the header fields with the specified $name.  In scalar context,
only the first fitting $name is returned.  Even when only one $name is
specified, multiple lines may be returned: some fields appear more than
once in a header.  Calls M<Mail::Message::Replace::MailHeader::get()>
=cut

sub get(@) { shift->head->get(@_) }

=method delete $name, [$index]]
Delete the fields with the specified $name.  The deleted fields are
returned.

BE WARNED: if no $name is specified, the C<delete> is interpreted as
the deletion of the message in a folder, so M<Mail::Box::Message::delete()>
will be called.  This may have no negative effect at all...

Calls M<Mail::Message::Replace::MailHeader::delete()>

=cut

sub delete(@)
{   my $self = shift;
    @_ ?  $self->head->delete(@_) : $self->SUPER::delete;
}

=section The body

=method body $lines|@lines
Returns an ARRAY of lines, representing the body.  With arguments, a
new body will be created.  In L<Mail::Internet>, the body is not an
object but a simple array.

BE WARNED: this overrules the M<Mail::Message::body()> method, which
may cause some confusion.  Use M<bodyObject()> to get access to that
body's data.

=cut

sub body(@)
{   my $self = shift;

    unless(@_)
    {   my $body = $self->body;
        return defined $body ? scalar($body->lines) : [];
    }

    my $data = ref $_[0] eq 'ARRAY' ? shift : \@_;
    my $body  = Mail::Message::Body::Lines->new(data => $data);
    $self->body($body);

    $body;
}

=method print_body [$fh]
Prints the body to the specified $fh, which defaults to STDOUT.  This
calls M<Mail::Message::Body::print()>.
=cut

sub print_body(@) { shift->SUPER::body->print(@_) }

=method bodyObject [$body]
Calls M<Mail::Message::body()>, because that C<body> method is overruled
by the one which has a L<Mail::Internet> compatible interface.
=cut

sub bodyObject(;$) { shift->SUPER::body(@_) }

=method remove_sig [$nrlines]
Remove the signature of a message with a maximum of $nrlines lines, which
defaults to 10.  The work is done on the decoded body content, by
M<Mail::Message::Body::stripSignature()>.
=cut

sub remove_sig(;$)
{   my $self  = shift;
    my $lines = shift || 10;
    my $stripped = $self->decoded->stripSignature(max_lines => $lines);
    $self->body($stripped) if defined $stripped;
    $stripped;
}

=method tidy_body
Removes blank lines from begin and end of the body.
=cut

sub tidy_body(;$)
{   my $self  = shift;

    my $body  = $self->body or return;
    my @body  = $body->lines;

    shift @body while @body &&  $body[0] =~ m/^\s*$/;
    pop   @body while @body && $body[-1] =~ m/^\s*$/;

    return $body if $body->nrLines == @body;
    my $new = Mail::Message::Body::Lines->new(based_on => $body, data=>\@body);
    $self->body($new);
}

=method smtpsend %options
This method is calling M<Mail::Message::send()> via C<smtp>, which is
implemented in M<Mail::Transport::SMTP>.  The implementation is
slightly different, so this method is not 100% compliant.

=option  MailFrom STRING
=default MailFrom C<$ENV{MAILADDRESS}> or $ENV{USER}
Your e-mail address.  This simulated L<Mail::Internet> object does not
try to create an e-mail address from the sendmail configuration file,
because that is generally a bad idea in environments with virtual hosts,
as we have now-adays.

=option  Hello STRING
=default Hello <helo_domain from Net::Config>

=option  Port INTEGER
=default Port 25

=option  Host HOSTNAME
=default Host C<$ENV{SMTPHOSTS} or from Net::Config>
Only the first detected HOSTNAME is taken, so differs from the original
implementation.

=option  Debug BOOLEAN
=default Debug <false>

=cut

sub smtpsend(@)
{   my ($self, %args) = @_;
    my $from = $args{MailFrom} || $ENV{MAILADDRESS} || $ENV{USER} || 'unknown';
    $args{helo}       ||= delete $args{Hello};
    $args{port}       ||= delete $args{Port};
    $args{smtp_debug} ||= delete $args{Debug};

    my $host  = $args{Host};
    unless(defined $host)
    {   my $hosts = $ENV{SMTPHOSTS};
        $host = (split /\:/, $hosts)[0] if defined $hosts;
    }
    $args{host} = $host;

    $self->send(via => 'smtp', %args);
}

=section The whole message as text

=method as_mbox_string
Returns the whole message as one string, which can be included in an
MBOX folder (while not using M<Mail::Box::Mbox>).  Lines in the body
which start with C<From > are escaped with an E<gt>.
=cut

sub as_mbox_string()
{   my $self    = shift;
    my $mboxmsg = Mail::Box::Mbox->coerce($self);

    my $buffer  = '';
    my $file    = Mail::Box::FastScalar->new(\$buffer);
    $mboxmsg->print($file);
    $buffer;
}

=section The nasty bits

=cut

BEGIN {
 no warnings;
 *Mail::Internet::new = sub (@)
   { my $class = shift;
     Mail::Message::Replace::MailInternet->new(@_);
   };
}

=ci_method isa $class
Of course, the C<isa()> class inheritance check should not see our
nasty trick.
=cut

sub isa($)
{   my ($thing, $class) = @_;
    return 1 if $class eq 'Mail::Internet';
    $thing->SUPER::isa($class);
}

=section Internals

=c_method coerce $message
Coerce (adapt type) of the specified $message (anything
M<Mail::Message::coerce()> accepts) into an M<Mail::Internet> simulating
object.
=cut

sub coerce() { confess }


1;

