package Mail::Box::FastScalar;

=chapter NAME

Mail::Box::FastScalar - fast alternative to IO::Scalar

=chapter DESCRIPTION

Contributed by "Todd Richmond" (richmond@proofpoint.com)  This package
should be released as separate package, but till then is incorporated
in the Mail::Box module.

Extremely fast L<IO::Scalar> replacement - >20x improvement in
getline(s)()

=section Warnings

You cannot modify the original reference between calls unless you
C<$obj->seek(1, 0)> to reset the object - VERY rare usage case

$/ must be undef or string - "" and \scalar unimplemented

=cut

use strict;
use warnings;
use integer;

sub new($) {
    my ($class, $ref) = @_;
    my $self = { ref => $ref, data => defined($$ref) ? $$ref : '' };

    bless $self, $class;
    return $self;
}

sub autoflush() {}

sub binmode() {}

sub clearerr { return 0; }

sub flush() {}

sub sync() { return 0; }

sub opened() { return $_[0]->{ref}; }

sub open($) {
    my $self = $_[0];

    $self->{ref} = $_[1];
    $self->{data} = ${$self->{ref}};
}

sub close() {
    my $self = $_[0];

    $self->{data} = '';
    undef $self->{ref};
}

sub eof() {
    my $self = $_[0];

    return length($self->{data}) == 0;
}

sub getc() {
    my $self = $_[0];

    return substr($self->{data}, 0, 1, '');
}

sub print {
    my $self = shift();
    my $buf = $#_ ? join('', @_) : $_[0];
    my $ref = $self->{ref};
    my $len = length($self->{data});

    if ($len == 0) {
	$$ref .= $buf;
    } else {
	my $pos = length($$ref) - $len;

	$len = length($buf);
	substr($$ref, $pos, $len) = $buf;
	$self->{data} = substr($$ref, $pos + $len, -1);
    }
    return 1;
}

sub read($$;$) {
    my $self = $_[0];
    my $buf = substr($self->{data}, 0, $_[2], '');

    ($_[3] ? substr($_[1], $_[3]) : $_[1]) = $buf;
    return length($buf);
}

sub sysread($$;$) {
    return shift->read(@_);
}

sub seek($$) {
    my $self = $_[0];
    my $whence = $_[2];
    my $ref = $self->{ref};
    my $len = length($$ref);
    my $pos;

    if ($whence == 0) {
	$pos = $_[1];
    } elsif ($whence == 1) {
	$pos = $len - length($self->{data}) + $_[1];
    } elsif ($whence == 2) {
	$pos = $len - length($self->{data}) - $_[1];
    } else {
	return;
    }

    if ($pos > $len) {
	$pos = $len;
    } elsif ($pos < 0) {
	$pos = 0;
    }
    $self->{data} = substr($$ref, $pos);
    return 1;
}

sub sysseek($$) {
    return $_[0]->seek($_[1], $_[2]);
}

sub setpos($) {
    return $_[0]->seek($_[1], 0);
}

sub sref() {
    return $_[0]->{ref};
}

sub getpos() {
    my $self = $_[0];

    return length(${$self->{ref}}) - length($self->{data});
}

sub tell() {
    my $self = $_[0];

    return length(${$self->{ref}}) - length($self->{data});
}

sub write($$;$) {
    my $self = $_[0];
    my $buf = substr($_[1], $_[3] || 0, $_[2]);
    my $ref = $self->{ref};
    my $len = length($self->{data});

    if ($len == 0) {
	$$ref .= $buf;
    } else {
	my $pos = length($$ref) - $len;

	$len = length($buf);
	substr($$ref, $pos, $len) = $buf;
	$self->{data} = substr($$ref, $pos + $len, -1, '');
    }
    return $len;
}

sub syswrite($;$$) {
    return shift()->write(@_);
}

sub getline() {
    my $self = $_[0];
    my $data = \$self->{data};

    if ((my $idx = index($$data, $/)) == -1 || !defined($/)) {
	my $r = $$data;

	return unless (length($r) > 0);
	$$data = '';
	return $r;
    } else {
	return substr($$data, 0, $idx + 1, '');
    }
}

sub getlines() {
    my $self = $_[0];
    my $data = $self->{data};
    my @lines;

    $self->{data} = '';
    if (defined($/)) {
	my $idx;

	while (($idx = index($data, $/)) != -1) {
	    push(@lines, substr($data, 0, $idx + 1, ''));
	}
    }
    push(@lines, $data) if (length($data) > 0);
    return wantarray() ? @lines : \@lines;
}

sub TIEHANDLE {
    ((defined($_[1]) && UNIVERSAL::isa($_[1], "Mail::Box::FastScalar"))
         ? $_[1] : shift->new(@_));
}

sub GETC { shift()->getc(@_) }
sub PRINT { shift()->print(@_) }
sub PRINTF { shift()->print(sprintf(shift, @_)) }
sub READ { shift()->read(@_) }
sub READLINE { wantarray ? shift()->getlines(@_) : shift()->getline(@_) }
sub WRITE { shift()->write(@_); }
sub CLOSE { shift()->close(@_); }
sub SEEK { shift()->seek(@_); }
sub TELL { shift()->tell(@_); }
sub EOF { shift()->eof(@_); }

1;
