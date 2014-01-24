
use strict;
use warnings;

package Mail::Server::IMAP4::List;

=chapter NAME

Mail::Server::IMAP4::List - folder related IMAP4 answers

=chapter SYNOPSIS

 my $imap = Mail::Server::IMAP4::List->new
   ( folders   => $folders   # M<Mail::Box::Identity>
   , inbox     => $inbox     # M<Mail::Box>
   , delimiter => '#'
   );

 my $imap = Mail::Server::IMAP4::List->new(user => $user);
 print $imap->list(...);        # for LIST command

=chapter DESCRIPTION

=chapter METHODS

=section Constructors

=c_method new $user

Create a (temporary) object to handle the LIST requests for
a certain user, based upon a set of folders.  The data is kept by
M<Mail::Box::Identity> and M<Mail::Box::Collection> objects, which
mean that the folders will not be opened to answer these questions.

=option  delimeter STRING|CODE
=default delimeter '/'
Either the constant delimiter, or a code reference which will get passed
a folder name and should return the delimiter string used in that name.
If that folder name is empty, the default delimiter must be reported.
See M<delimiter()> for an example.

=option  folders  OBJECT
=default folders  <from user>
You need to specify either a set of folders explicitly or via the
user. Some M<Mail::Box::Identity> OBJECT is needed.

=option  inbox    BOOLEAN
=default inbox    <from user>
For now, only used to see whether there is an inbox, so a truth value will
do.  This may change in the future.  By default, the flag is set if
C<$user->inbox> is defined.

=option  user     OBJECT
=default user     <undef>
A M<Mail::Box::Manage::User> OBJECT, representing the user who's folders
must get reported.
=cut

sub new($)
{   my ($class, %args) = @_;

    my $self = bless {}, $class;

    my $user = $self->{MSIL_user}  = $args{user};
    $self->{MSIL_folders} = $args{folders};
    $self->{MSIL_inbox}   = $args{inbox};
    $self->{MSIL_delim}   = exists $args{delimiter} ? $args{delimiter} : '/';
    $self;
}

#------------------------------------------

=section Attributes

=method delimiter [$foldername]
Returns the delimiter string.  The foldername is only required when a
CODE reference was specified at initiation.

=example setting-up an IMAP4 delimeter
 sub delim($)
 {   my $path = shift;
     my ($delim, $root)
       = $path =~ m/^(#news\.)/ ? ('.', $1)
       = $path =~ m!^/!         ? ('/', '/')
       :                          ('/', '');

     wantarray ? ($delim, $root) : $delim;
 }

 my $list = Mail::Server::IMAP4::List->new(delimiter => \&delim, ...);
 print $list->delimiter('abc/xyz');      # returns a / (slash) and ''
 print $list->delimiter('#news.feed');   # returns a . (dot)   and $news.
 print $list->delimiter('');             # returns default delimiter
 
=cut

sub delimiter(;$)
{   my $delim = shift->{MSIL_delim};
    ref $delim ? $delim->(shift) : $delim;
}

#------------------------------------------

=method user
Returns the M<Mail::Box::Manage::User> object, if defined.
=cut

sub user() { shift->{MSIL_user} }

#------------------------------------------

=method folders
Returns the M<Mail::Box::Identity> of the toplevel folder.
=cut

sub folders()
{   my $self = shift;
    $self->{MSIL_folders} || $self->user->topfolder;
}

#------------------------------------------

=method inbox
Returns the M<Mail::Box> or filename of the INBOX.
=cut

sub inbox()
{   my $self = shift;
    $self->{MSIL_inbox} || $self->user->inbox;
}

#------------------------------------------

=section IMAP Commands

=method list $base, $pattern
IMAP's LIST command.  The request must be partially decoded, the answer
will need to be encoded.

=examples using IMAP list
 my $imap  = Mail::Server::IMAP4::List->new(delimiter => \&delim, ...);
 local $"  = ';';

 my @lines = $imap->list('', '');  # returns the default delimiter
 print ">@{$lines[0]}<";           #  >(\Noselect);/;<

 my @lines = $imap->list('#news',''); # specific delimiter
 print ">@{$lines[0]}<";           #  >(\Noselect);.;<

 my @lines = $imap->list('top/x/', '%');
 print ">@$_<," foreach @lines;    #  >();/;/tmp/x/y<,>(\Marked);/;/tmp/x/z<

=cut

sub list($$)
{   my ($self, $base, $pattern) = @_;
    
    return [ '(\Noselect)', $self->delimiter($base), '' ]
       if $pattern eq '';

    my $delim  = $self->delimiter($base);
    my @path   = split $delim, $base;
    my $folder = $self->folders;

    while(@path && defined $folder)
    {   $folder = $folder->folder(shift @path);
    }
    defined $folder or return ();

    my @pattern = split $delim, $pattern;
    return $self->_list($folder, $delim, @pattern);
}

sub _list($$@)
{   my ($self, $folder, $delim) = (shift, shift, shift);

    if(!@_)
    {   my @flags;
        push @flags, '\Noselect'
           if $folder->onlySubfolders || $folder->deleted;

        push @flags, '\Noinferiors' unless $folder->inferiors;
        my $marked = $folder->marked;
        push @flags, ($marked ? '\Marked' : '\Unmarked')
            if defined $marked;

        local $" = ' ';

        # This is not always correct... should compose the name from the
        # parts... but in nearly all cases, the following is sufficient.
        my $name = $folder->fullname;
        for($name)
        {    s/^=//;
             s![/\\]!$delim!g;
        }
        return [ "(@flags)", $delim, $name ];
    }

    my $pat = shift;
    if($pat eq '%')
    {   my $subs = $folder->subfolders
             or return $self->_list($folder, $delim);
        return map { $self->_list($_, $delim, @_) } $subs->sorted;
    }

    if($pat eq '*')
    {   my @own = $self->_list($folder, $delim, @_);
        my $subs = $folder->subfolders or return @own;
        return @own, map { $self->_list($_, $delim, '*', @_) } $subs->sorted;
    }

    $folder = $folder->find(subfolders => $pat) or return ();
    $self->_list($folder, $delim, @_);
}

#------------------------------------------

=chapter DETAILS

See
=over 4
=item RFC2060: "Internet Message Access Protocol IMAP4v1"
sections 6.3.8 (LIST question) and 7.2.2 (LIST answer)
=back

=cut

1;
