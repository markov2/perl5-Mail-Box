use strict;
use warnings;

package Mail::Box::Parser::C;
use base 'Mail::Box::Parser';

$break_the_compiler_which_has_bug_Now_the_Perl_version_is_used;
BEGIN {warn "C Parser loaded.\n"}

our $VERSION = 2.00_18;

=head1 NAME

Mail::Box::Parser::C - Reading messages in C

=head1 CLASS HIERARCHY

 Mail::Box::Parser::C
 is a Mail::Box::Parser
 is a Mail::Reporter

=head1 SYNOPSIS

=head1 DESCRIPTION

The C<Mail::Box::Parser::C> implements parsing of messages in the C
programming language using C<Inline::C>.  When C<Inline::C> is not
installed, the Perl parser will be used instead.

=head1 METHOD INDEX

The general methods for C<Mail::Box::Parser::C> objects:

  MBP bodyAsFile FILEHANDLE [,CHA...   MBP popSeparator
  MBP bodyAsList [,CHARS [,LINES]]     MBP pushSeparator STRING
  MBP bodyAsString [,CHARS [,LINES]]   MBP readHeader WRAP
  MBP bodyDelayed [,CHARS [,LINES]]    MBP readSeparator OPTIONS
  MBP defaultParserType [CLASS]         MR report [LEVEL]
   MR errors                            MR reportAll [LEVEL]
  MBP foldHeaderLine LINE, LENGTH      MBP setPosition WHERE
  MBP inDosmode                        MBP start OPTIONS
   MR log [LEVEL [,STRINGS]]           MBP stop
  MBP new [OPTIONS]                     MR trace [LEVEL]

The extra methods for extension writers:

   MR DESTROY                           MR logPriority LEVEL
   MR inGlobalDestruction               MR logSettings

Methods prefixed with an abbreviation are described in the following
manual-pages:

   MR = L<Mail::Reporter>
  MBP = L<Mail::Box::Parser>

=head1 METHODS

=over 4

=cut

use Inline C       => 'DATA'
         , CCFLAGS => '-Wall'
         , NAME    => 'Mail::Box::Parser::C'
         , PREFIX  => 'MBPC_';

Inline->init;

#------------------------------------------

#### implemented in C, down in this file.
sub open_file(@);
sub close_file($);
sub read_header($$);
sub fold_header_line($$);
sub struct_DESTROY($);
sub get_position($);
sub set_position($$);
sub in_dosmode($);
sub push_separator($$);
sub pop_separator($);
sub read_separator($);
sub body_as_string($$$);
sub body_as_list($$$);
sub body_as_file($$$$);
sub body_delayed($$$);
####

sub init(@)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);
    $self->{MBPC_trace_level} = $self->logPriority($args->{trace});

    $self;
}

sub start(@)
{   my $self = shift;

    return $self
       if $self->{MBPC_file};   # already started.

    $self->SUPER::start(@_)
       or return;

    my $file = $self->{MBPC_file} = open_file
     ( $self->{MBP_filename}
     , $self->{MBPC_trace_level}
     , $self->{MBP_mode}
     );

    $file ? $self : undef;
}

sub stop(@)
{   my $self = shift;

    my $file = delete $self->{MBPC_file}
        or return;              # already closed

    $self->SUPER::stop(@_);

    close_file $file;
    $self;
}

sub DESTROY
{   my $self = shift;
    my $file = delete $self->{MBPC_file};
    struct_DESTROY $file if $file;
}

sub filePosition(;$)
{   my $self = shift;
    @_ ? set_position $self->{MBPC_file}, shift
       : get_position $self->{MBPC_file};
}

sub readHeader($)   {read_header shift->{MBPC_file}, shift }

sub foldHeaderLine($$)
{   my ($class, $name, $length) = @_;

      length $name < $length
    ? $name
    : fold_header_line $name, $length;
}

sub bodyAsString(@)
{   my ($self, $chars, $lines) = @_;
    body_as_string $self->{MBPC_file}, $chars || -1, $lines || -1;
}

sub bodyAsList(@)
{   my ($self, $chars, $lines) = @_;
    body_as_list $self->{MBPC_file}, $chars || -1, $lines || -1;
}

sub bodyAsFile(@)
{   my ($self, $file, $chars, $lines) = @_;
    body_as_file $self->{MBPC_file}, $file, $chars || -1, $lines || -1;
}

sub bodyDelayed(@)
{   my ($self, $chars, $lines) = @_;
    my ($w, $c, $l)
      = body_delayed $self->{MBPC_file}, $chars || -1, $lines || -1;

    undef $l if defined $l && $l==-1;
    ($w, $c, $l);
}

sub inDosmode()      { in_dosmode     shift->{MBPC_file} }
sub pushSeparator($) { push_separator shift->{MBPC_file}, shift }
sub popSeparator()   { pop_separator  shift->{MBPC_file} }
sub readSeparator()  { read_separator shift->{MBPC_file} }

#------------------------------------------

1;

__DATA__
__C__

#define TRACE_INTERNAL  7  /* synchronize this with the %trace_levels */
#define NO_TRACE        6
#define TRACE_ERRORS    5
#define TRACE_WARNINGS  4
#define TRACE_PROGRESS  3
#define TRACE_NOTICES   2
#define TRACE_DEBUG     1

#ifndef MAX_LINE
#define MAX_LINE        1024
#endif

#ifndef NULL
#define NULL
#endif

#ifndef EOL
#define EOL  '\0'
#endif

#ifndef CR
#define CR   '\015'
#endif

#ifndef LF
#define LF   '\012'
#endif

#define MAX_FOLD       512
#define FOLDSTART      "        "
#define COPYSIZE       4096

#define GETBOX(OBJECT) ((Mailbox *)SvIV(OBJECT))

typedef struct separator
{   char             * line;
    int                length;
    struct separator * next;
} Separator;

typedef struct
{   char      * filename;
    FILE      * file;

    int         trace;

    Separator * separators;
    int         strip_gt;

    int         dosmode;
    char        line[MAX_LINE+1];
    long        line_start;
    int         keep_line;      /* unget line */
} Mailbox;

/*
 * OPEN_FILE
 */

SV *MBPC_open_file(char *name, int trace, char *mode)
{ 
    Mailbox * box;
    SV      * obj;
    int       filename_length;

/*fprintf(stderr, "mailbox\n");*/
    New(0, box, 1, Mailbox);
    obj               = newSViv((IV)box);
    SvREADONLY_on(obj);

    box->keep_line    = 0;
    box->strip_gt     = 0;
    box->dosmode      = 1;  /* will be set to 0 if not true */
    box->separators   = NULL;

    /* Open the file. */
    box->file = fopen(name, mode);
    if(box->file==NULL)
    {   fprintf(stderr, "Unable to open file %s for %s.\n", name, mode);
        Safefree(box);
        return &PL_sv_undef;
    }

    /* Copy the filename. */
    filename_length   = strlen(name);
/*fprintf(stderr, "filename %ld\n", (long)filename_length);*/
    New(0, box->filename, filename_length+1, char);
    strcpy(box->filename, name);

/*fprintf(stderr, "Open is done.\n");*/
    return obj;
}

void MBPC_close_file(SV *obj)
{   Mailbox   *box = GETBOX(obj);
    Separator *sep;

    if(box==NULL) return;
    if(box->file==NULL) return;   /* already closed */

    fclose(box->file);
    box->file = NULL;

    sep = box->separators;
    while(sep!=NULL)
    {   Separator * next = sep->next;
        Safefree(sep->line);
        Safefree(sep);
        sep = next;
    }
}

void MBPC_struct_DESTROY(SV* obj)
{   Mailbox *box = GETBOX(obj);
    if(box==NULL) return;

    sv_setiv(obj, (IV)NULL);
    Safefree(box->filename);
    Safefree(box);
}

void MBPC_push_separator(SV *obj, char *line_start)
{   Mailbox    *box = GETBOX(obj);
    Separator  *sep;
    if(box==NULL) return;

/*fprintf(stderr, "separator\n");*/
    New(0, sep, 1, Separator);
    sep->length     = strlen(line_start);

/*fprintf(stderr, "separator %ld\n", (long)sep->length+1);*/
    New(0, sep->line, sep->length+1, char);
    strcpy(sep->line, line_start);

    sep->next       = box->separators;
    box->separators = sep;

    if(strncmp(sep->line, "From ", sep->length)==0)
        box->strip_gt++;
}

SV* MBPC_pop_separator(SV *obj)
{   Mailbox   *box = GETBOX(obj);
    Separator *old;
    SV        *line;

    if(box==NULL) return &PL_sv_undef;

    old = box->separators;
    if(old==NULL) return &PL_sv_undef;

    if(strncmp(old->line, "From ", old->length)==0)
        box->strip_gt--;

    box->separators = old->next;
    line = newSVpv(old->line, old->length);

    Safefree(old->line);
    Safefree(old);
    return line;
}

static char * get_one_line(Mailbox *box)
{
    if(box->keep_line)
    {   box->keep_line = 0;
        return box->line;
    }

    box->line_start = ftell(box->file);
    if(!fgets(box->line, MAX_LINE, box->file))
        return NULL;

    if(box->dosmode)
    {   int len = strlen(box->line);
        if(len >= 2 && box->line[len-2]==CR)
        {   box->line[len-2] = LF;          /* Remove CR's before LF's       */
            box->line[len-1] = EOL;
        }
        else
        if(len==0 || box->line[len-1]!=LF)  /* Last line on Win* may lack    */
        {   box->line[len]   = LF;          /*    newline.  Add it silently  */
            box->line[len+1] = EOL;
        }
        else box->dosmode = 0;              /* Apparently not dosmode at all */
    }

    return box->line;
}

/*
 * file_position
 * Give the file-position of the line to be processed.
 */

static long file_position(Mailbox *box)
{   return box->keep_line ? box->line_start : ftell(box->file);
}

long MBPC_get_position(SV *obj, long where)
{   Mailbox *box = GETBOX(obj);
    if(box==NULL) return 0;
    return file_position(box);
}

int MBPC_set_position(SV *obj, long where)
{   Mailbox *box = GETBOX(obj);
    if(box==NULL) return 0;
    return fseek(box->file, where, SEEK_SET)==0;
}

/*
 * read_header
 */

static int read_header_line(Mailbox *box, SV **field, SV **content);

void MBPC_read_header(SV *obj, int wrap)
{   Mailbox *box = GETBOX(obj);
    SV      *field, *content;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL || box->file==NULL)
        Inline_Stack_Done;                 /* returns */

    Inline_Stack_Push(sv_2mortal(newSViv((IV)file_position(box))));

    while(read_header_line(box, &field, &content))
    {   Inline_Stack_Push(sv_2mortal(field));
        Inline_Stack_Push(sv_2mortal(content));
    }
 
    Inline_Stack_Done;
}

static int read_header_line(Mailbox *box, SV **field, SV **content)
{
    char * line   = get_one_line(box);
    char * begin;
    char * reader;
    int    length, field_error;

    if(line==NULL)    return 0;  /* end of file.          */
    if(line[0]=='\n') return 0;  /* normal end of header. */

    /*
     * Read the header's field.
     */

    for(begin = line; isspace(*begin); begin++)
        ;

    for(reader = begin; *reader!=':' && *reader!='\n'; reader++)
        ;

    if(*reader=='\n')
    {   fprintf(stderr, "Unexpected end of header:\n  %s", line);
        box->keep_line = 1;
        return 0;
    }

    field_error = 0;
    for(length=reader-begin-1; length >= 0 && isspace(begin[length]); --length)
        field_error++;

    if(field_error && box->trace <= TRACE_WARNINGS)
    {   fprintf(stderr, "Blanks stripped after header-fieldname:\n  %s",line);
    }

    *field = newSVpvn(begin, length+1);

    /*
     * Now read the content.
     */

    /* skip starting blanks. */
    for(++reader; isspace(*reader); ++reader)
        ;
    begin = reader;

    /* to end of line. */
    while(*reader!='\n') reader++;

    /* skip trailing blanks. */
    while(reader >= begin && isspace(*reader))
        *reader-- = EOL;

    if(reader < begin && box->trace <= TRACE_NOTICES)
        fprintf(stderr, "Empty header content for field %s", line);
   
    *content = newSVpv(begin, 0);

    /*
     * Let's do some unfolding.  We read a line more, which may
     * be not related to this one... but happily it can be unget.
     */

    while(1)
    {   line = get_one_line(box);
        if(line==NULL) break;

        if(!isspace(line[0]) || line[0]=='\n' )
        {   box->keep_line = 1;
            break;
        }

        /* skip all but one blank. */
        while(isspace(line[1])) line++;
        line[0] = ' ';

        /* strip blanks at end line, which is allowed for structured fields. */
        reader = line+strlen(line)-1;
        while(reader>=line && isspace(*reader)) *reader-- = EOL;

        /* append stripped line. */
        sv_catpvn(*content, line, reader-line+1);
    }

    return 1;
}

/*
 * fold_header_line
 * Fold an (already unfolded) line.
 */

void MBPC_fold_header_line(char *original, int wrap)
{   char   unfolded[MAX_FOLD+1];
    char   copy    [MAX_FOLD+2];
    char * line;
    Inline_Stack_Vars;

    Inline_Stack_Reset;

    if(wrap > MAX_FOLD)
    {   fprintf( stderr
               , "Error: fold-size maximum too low: is %d, requires %d\n"
               , (int)MAX_FOLD, (int)wrap);
        exit(EINVAL);
    }

    /*
     * First unfold.
     */

    {   char *reader = original;
        char *writer = unfolded;
        while(*reader != EOL)
        {   char c = *reader++;
            if(isspace(c))
            {   *writer++ = ' ';
                while(isspace(*reader))
                    reader++;
            }
            else
                *writer++ = c;
        }

        while(writer > unfolded && isspace(writer[-1]))
            writer--;

        *writer = EOL;
    }

    /*
     * Now fold again
     */

    copy[0] = EOL;
    line    = unfolded;

    while(*line != EOL)
    {   int length      = strlen(line);
        int take        = length;
        int found       = 0;
        int strlen_copy = strlen(copy);
        int wrap_left   = wrap - strlen_copy;

        /*
         * Got to the tail?
         */

        if(length <= wrap_left)
            found = 1;

        if(!found)
        {   for(take = wrap_left; take>20; take--)
                if(line[take]==';')
                {   found = 1;
                    take++;
                    break;
                }
        }

        if(!found)
        {   for(take = wrap_left; take>20; take--)
                if(line[take]==',')
                {   found = 1;
                    take++;
                    break;
                }
        }

        if(!found)
        {   for(take = wrap_left; take>20; take--)
                if(line[take]==' ')
                {   found = 1;
                    take++;
                    break;
                }
        }

        if(!found)
        {   for(take = wrap_left; take>20; take--)
                if(line[take]=='.')
                {   found = 1;
                    take++;
                    break;
                }
        }

        if(!found)
        {   take = wrap_left;
            while(take < MAX_FOLD - strlen_copy && line[take] != EOL)
            {   char this = line[take++];
                if(this==','||this==';'||this=='.'||this==' ')
                {   found = 1;
                    break;
                }
            }
        }

        strncat(copy, line, take);
        strcat(copy, "\n");
fprintf(stderr, "Allocating %d bytes for line.\n", strlen(copy));
        Inline_Stack_Push(sv_2mortal(newSVpv(copy, 0)));

        line += take;
        while(isspace(*line)) line++;  /* skip blanks. */

        strcpy(copy, FOLDSTART);
    }

    Inline_Stack_Done;
}

/*
 * in_dosmode
 */

int MBPC_in_dosmode(SV *obj)
{   Mailbox *box = GETBOX(obj);
    if(box==NULL) return 0;
    return box->dosmode;
}

/*
 * is_good_end
 * Look if the predicted size of the message may be real.  Real means
 * that after the given location is end-of-file, or some blank lines
 * and then the active separator.
 *
 * This function returns whether this seems the right end.
 */

static int is_good_end(Mailbox *box, long where)
{   char      *line;
    int        found;
    Separator *sep;
    long       old_location;

    sep   = box->separators;
    if(sep==NULL) return 1;       /* no seps, than we have to trust it. */

    old_location   = file_position(box);
    if(where >= 0)
    {   if(fseek(box->file, where, SEEK_SET)!=0)
        {   /* File too short. */
            fseek(box->file, old_location, SEEK_SET);
            return 0;             /* Impossible seek. */
        }
    }

    box->keep_line = 0;           /* carefully destroy unget-line. */

    line = get_one_line(box);     /* find first non-empty line. */
    while(line!=NULL && line[0]=='\n' && line[1]==EOL)
        line = get_one_line(box);

    found = (line==NULL || strncmp(line, sep->line, sep->length)==0);

    fseek(box->file, old_location, SEEK_SET);
    return found;
}

/*
 * read_separator
 * Return a line with the last defined separator.  Empty lines before this
 * are permitted, but no other lines.
 */

void MBPC_read_separator(SV *obj)
{   Mailbox   *box  = GETBOX(obj);
    Separator *sep;
    char      *line;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL) Inline_Stack_Return(0);

    sep = box->separators;    /* Never success when there is no sep */
    if(sep==NULL) Inline_Stack_Return(0);

    line = get_one_line(box);  /* Get first real line. */
    while(line!=NULL && line[0]=='\n' && line[1]==EOL)
        line = get_one_line(box);

    if(line==NULL)             /* eof reached. */
        Inline_Stack_Return(0);

    if(strncmp(sep->line, line, sep->length)!=0)
    {   box->keep_line = 1;
        Inline_Stack_Return(0);
    }

    Inline_Stack_Push(sv_2mortal(newSViv(box->line_start)));
    Inline_Stack_Push(sv_2mortal(newSVpv(line, strlen(line))));
    Inline_Stack_Return(2);
}

/*
 * read_stripped_lines
 * In dosmode, each line must be stripped from the \r, and
 * when we have the From-line seperator, /^>+From / must be stripped
 * from one >.
 *
 * Reading from a Windows file will translate \r\n into \n.  But it
 * is hard to find-out if this is the case.  However, the Content-Length
 * field count these line-seps both.  That's why the ftell() is asked
 * to provide the real location.
 */

static char **read_stripped_lines(Mailbox *box,
    int expect_chars, int expect_lines,
    int *nr_chars,    int *nr_lines)
{   char   ** lines      = (char**)1;  /* true */
    int       max_lines;
    long      start      = file_position(box);

    max_lines  = expect_lines > 10 ? expect_lines : 1000;

fprintf(stderr, "maxlines %ld\n", (long)max_lines);
    New(0, lines, max_lines, char *);
    *nr_lines = 0;
    *nr_chars = 0;

    while(1)
    {   char      *line;
        char      *linecopy;
        Separator *sep;
        int        length;

        if(*nr_lines == expect_lines && is_good_end(box, -1))
            break;

        if(file_position(box)-start == expect_chars && is_good_end(box,-1))
            break;

        line = get_one_line(box);
        if(line==NULL)
        {   /* remove empty line before separator.*/
            if(*nr_lines>0 && box->separators)
            {   char *prev = lines[*nr_lines -1];
                if(prev[0]=='\n' && prev[1]==EOL)
                {   (*nr_lines)--;
                    (*nr_chars)--;
                }
                Safefree(prev);
            }
            break;
        }

        /*
         * Check for separator
         */

        sep = box->separators;
        while(sep != NULL && strncmp(sep->line, line, sep->length)!=0)
            sep = sep->next;

        if(sep!=NULL)
        {   /* Separator found */
            box->keep_line = 1;        /* keep separator line to read later.  */
            if(*nr_lines > 0)          /* remove empty line before separator. */
            {   char *prev = lines[*nr_lines -1];
                if(prev[0]=='\n' && prev[1]==EOL)
                {   (*nr_lines)--;
                    (*nr_chars)--;
                    Safefree(prev);
                }
            }

            break;
        }

        /*
         *   >>>>From becomes >>>From
         */

        if(box->strip_gt && line[0]=='>')
        {   char *reader = line;
            while(*reader == '>') reader++;
            if(strncmp(reader, "From ", 5)==0)
               line++;
        }

        /*
         * Store line
         */

        if(*nr_lines >= max_lines)
        {   max_lines *= 1.5;
fprintf(stderr, "Maxlines = %ld\n", (long)max_lines);
            lines = Renew(lines, max_lines, char *);
        }

        length           = strlen(line) +1;
fprintf(stderr, "Length = %ld\n", (long)length);
        New(0, linecopy, length, char);
        strcpy(linecopy, line);

        lines[*nr_lines] = linecopy;

        (*nr_lines)++;
        *nr_chars       += length;
    }

fprintf(stderr, "Reading stripped done\n");
    return lines;
}

/*
 * scan_stripped_lines
 * Like read_stripped_lines, but then without allocation memory.
 */

static int scan_stripped_lines(Mailbox *box,
    int expect_chars, int expect_lines,
    int *nr_chars,    int *nr_lines)
{   long      start      = file_position(box);
    int       last_blank = 0;

/*fprintf(stderr, "Scanning...\n");*/
    *nr_lines = 0;
    *nr_chars = 0;

    while(1)
    {   char      *line;
        Separator *sep;

        if(*nr_lines == expect_lines && is_good_end(box, -1))
            break;

        if(file_position(box)-start == expect_chars && is_good_end(box,-1))
            break;

        line = get_one_line(box);
        if(line==NULL)
        {   /* remove empty line before eof if separator.*/
            if(last_blank && box->separators)
            {   (*nr_lines)--;
                (*nr_chars)--;
                last_blank = 0;
            }
            break;
        }

        /*
         * Check for separator
         */

        sep = box->separators;
        while(sep != NULL && strncmp(sep->line, line, sep->length)!=0)
            sep = sep->next;

        if(sep!=NULL)
        {   /* Separator found */
            box->keep_line = 1;  /* keep separator line to read later  */
            if(last_blank)       /* remove empty line before separator */
            {   (*nr_lines)--;
                (*nr_chars)--;
                last_blank = 0;
            }
            break;
        }

        /*
         *   >>>>From becomes >>>From
         */

        if(box->strip_gt && line[0]=='>')
        {   char *reader = line;
            while(*reader == '>') reader++;
            if(strncmp(reader, "From ", 5)==0)
               line++;
        }

        /*
         * Count
         */

        (*nr_lines)++;
        *nr_chars += strlen(line);
        last_blank = (line[0]=='\n' && line[1]==EOL);
    }

/**hier**/
fprintf(stderr, "Scanning done\n");
    return 1;
}

/*
 * take_scalar
 * Take a block of file-data into one scalar, as efficient as possible.
 */

static SV* take_scalar(Mailbox *box, long begin, long end)
{
    char     buffer[COPYSIZE];
    size_t   tocopy = end - begin;
    size_t   bytes  = 1;
    SV      *result = newSVpv("", 0);

    /* pre-grow the scalar, so Perl doesn't need to re-alloc */
    SvGROW(result, tocopy);

    fseek(box->file, begin, SEEK_SET);
    while(tocopy > 0 && bytes > 0)
    {   int take = tocopy < COPYSIZE ? tocopy : COPYSIZE;
        bytes    = fread(buffer, take, 1, box->file);
        sv_catpvn(result, buffer, bytes);
        tocopy  -= bytes;
    }

    return result;
}

/*
 * body_as_string
 * Read the whole body into one scalar, and return it.
 * When lines need a post-processing, we read line-by-line.  Otherwise
 * we can read the block as a whole.
 */

void MBPC_body_as_string(SV *obj, int expect_chars, int expect_lines)
{   Mailbox *box    = GETBOX(obj);
    SV      *result;
    char   **lines;
    int      nr_lines=0, nr_chars=0, line_nr;
    long     begin;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL) Inline_Stack_Return(0);

    begin = file_position(box);

    if(!box->dosmode && !box->strip_gt && expect_chars >=0)
    {
        long  end = begin + expect_chars;

        if(is_good_end(box, end))
        {   Inline_Stack_Push(sv_2mortal(newSViv(begin)));
            Inline_Stack_Push(sv_2mortal(newSViv(fileposition(box))));
            Inline_Stack_Push(sv_2mortal(take_scalar(box, begin, end)));
            Inline_Stack_Return(3);
        }
    }

    lines = read_stripped_lines(box, expect_chars, expect_lines,
        &nr_chars, &nr_lines);

    if(lines==NULL)
        Inline_Stack_Return(0);

    /* Join the strings. */
    result = newSVpv("",0);
    SvGROW(result, nr_chars);

    for(line_nr=0; line_nr<nr_lines; line_nr++)
    {   sv_catpv(result, lines[line_nr]);
        Safefree(lines[line_nr]);
    }

    Safefree(lines);

    Inline_Stack_Push(sv_2mortal(newSViv(begin)));
    Inline_Stack_Push(sv_2mortal(newSViv(fileposition(box))));
    Inline_Stack_Push(sv_2mortal(result));
    Inline_Stack_Return(3);
}

/*
 * body_as_list
 * Read the whole body into a list of scalars.
 */

void MBPC_body_as_list(SV *obj, int expect_chars, int expect_lines)
{   Mailbox *box    = GETBOX(obj);
    char   **lines;
    int      nr_lines=0, nr_chars=0, line_nr;
    long     begin;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL) Inline_Stack_Return(0);

    begin = file_postition(box);
    lines = read_stripped_lines(box, expect_chars, expect_lines,
        &nr_chars, &nr_lines);

    if(lines==NULL)
        Inline_Stack_Return(0);

    Inline_Stack_Push(sv_2mortal(newSViv(begin)));
    Inline_Stack_Push(sv_2mortal(newSViv(file_position(box))));

    /* Allocating the lines for real. */

/*fprintf(stderr, "Allocating.\n");*/
    for(line_nr=0; line_nr<nr_lines; line_nr++)
    {   char *line = lines[line_nr];
        Inline_Stack_Push(newSVpv(line, 0));
        Safefree(line);
    }
/*fprintf(stderr, "Allocating Done.\n");*/

    Safefree(lines);
/*fprintf(stderr, "Safefree.\n");*/
    Inline_Stack_Done;
}

/*
 * body_as_file
 * Read the whole body into a file.
 */

void MBPC_body_as_file(SV *obj, FILE *out, int expect_chars, int expect_lines)
{   Mailbox *box    = GETBOX(obj);
    char   **lines;
    int      nr_lines=0, nr_chars=0, line_nr;
    long     begin;
    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL) Inline_Stack_Return(0);

    begin = file_postition(box);
    lines = read_stripped_lines(box, expect_chars, expect_lines,
        &nr_chars, &nr_lines);

    if(lines==NULL)
        Inline_Stack_Return(0);

    Inline_Stack_Push(sv_2mortal(newSViv(begin)));
    Inline_Stack_Push(sv_2mortal(newSViv((IV)file_position(box))));
    Inline_Stack_Push(sv_2mortal(newSViv((IV)nr_lines)));

    /* Join the strings. */

    for(line_nr=0; line_nr<nr_lines; line_nr++)
    {   fputs(lines[line_nr], out);
        Safefree(lines[line_nr]);
    }

    Safefree(lines);
    Inline_Stack_Done;
}

/*
 * body_delayed
 * Skip the whole body, only counting chars and lines.
 */

void MBPC_body_delayed(SV *obj, int expect_chars, int expect_lines)
{   Mailbox *box      = GETBOX(obj);
    char   **lines;
    int      nr_lines = 0, nr_chars = 0;
    long     begin    = file_position(box);

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box==NULL) Inline_Stack_Return(0);

    if(expect_chars >=0)
    {
        long  end    = begin + expect_chars;
        if(is_good_end(box, end))
        {   /*  Accept new end  */
            fseek(box->file, end, SEEK_SET);
            Inline_Stack_Push(sv_2mortal(newSViv((IV)begin)));
            Inline_Stack_Push(sv_2mortal(newSViv((IV)end)));
            Inline_Stack_Push(sv_2mortal(newSViv((IV)expect_chars)));
            Inline_Stack_Push(sv_2mortal(newSViv((IV)expect_lines)));
            Inline_Stack_Return(4);
        }
    }

    if(scan_stripped_lines(box, expect_chars, expect_lines,
        &nr_chars, &nr_lines))
    {   Inline_Stack_Push(sv_2mortal(newSViv((IV)begin)));
        Inline_Stack_Push(sv_2mortal(newSViv((IV)file_position(box))));
        Inline_Stack_Push(sv_2mortal(newSViv((IV)nr_chars)));
        Inline_Stack_Push(sv_2mortal(newSViv((IV)nr_lines)));
        Inline_Stack_Return(4);
    }

    Inline_Stack_Done;
}

__END__

=head1 SEE ALSO

L<Mail::Box-Overview>

=head1 AUTHOR

Mark Overmeer (F<mailbox@overmeer.net>).
All rights reserved.  This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 VERSION

This code is beta, version 2.00_11.

Copyright (c) 2001 Mark Overmeer. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
