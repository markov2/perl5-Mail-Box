use strict;
use warnings;

package Mail::Box::Parser::C;
use base 'Mail::Box::Parser';

# Parse mail-boxes in C.  See Mail::Box::Parser
#
# Copyright (c) 2001 Mark Overmeer. All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

our $VERSION = '2.00_04';

use Inline C       => 'DATA'
         , CCFLAGS => '-Wall'
         , NAME    => 'Mail::Box::Parser::C'
         , PREFIX  => 'MBPC_';

Inline->init;

init_log_labels();

#------------------------------------------

#### implemented in C, down in this file.
sub open_file(@);
sub close_file($);
sub read_header($);
sub fold_header_line($$);
sub struct_DESTROY($);
sub in_dosmode($);
sub push_separator($$);
sub pop_separator($);
sub read_separator($);
sub body_as_string($$$);
sub body_as_list($$$);
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

    $self->SUPER::DESTROY
        if Mail::Box::Parser->can('DESTROY');

    struct_DESTROY $self->{MBPC_file};
}

sub readHeader()
{   my $self = shift;
    read_header $self->{MBPC_file};
}

sub foldHeaderLine($$)
{   my ($class, $name, $length) = @_;
    $name =~ s/\s+/ /g;            # unfold first

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

#define MAXFOLD        512
#define FOLDSTART      "        "
#define COPYSIZE       4096

#define GETPTR(OBJECT) ((Mailbox *)SvIV(SvRV(OBJECT)))

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
    char        line[MAX_LINE];
    long        line_start;
    int         keep_line;      /* unget line */
} Mailbox;

static SV *notice, *progress, *warning, *error, *internal;
static void MBPC_log(Mailbox *box, SV *level, SV *text);

void MBPC_init_log_labels()
{
    internal = newSVpv("INTERNAL", 9);
    error    = newSVpv("ERROR",    5);
    warning  = newSVpv("WARNING",  7);
    progress = newSVpv("PROGRESS", 8);
    notice   = newSVpv("NOTICE",   6);
}

/*
 * OPEN_FILE
 *
 * Open a file-handle which is not visible in the Perl modules.  We
 * keep it this way to avoid possible unwanted interference by Perl
 * itself, or by bad written applications.
 *
 * The object-creation and destruction is taken from the
 * Inline::C-Cookbook manual page.
 */

SV *MBPC_open_file(char *name, int trace, char *mode)
{ 
    Mailbox * box     = (Mailbox *)malloc(sizeof(Mailbox));
    SV      * obj_ref = newSViv(0);
    SV      * obj     = newSVrv(obj_ref, NULL);

    if(box==NULL)
    {   fprintf(stderr, "No mem for Mailbox-structure.\n");
        exit(errno);
    }

    box->keep_line    = 0;
    box->strip_gt     = 0;
    box->dosmode      = 1;
    box->separators   = NULL;

    /* Copy the filename. */
    box->filename     = strdup(name);
    if(box->filename==NULL)
    {   fprintf(stderr, "Out of memory for filename %s.\n", name);
        return obj_ref;
    }

    /* Open the file. */

    box->file = fopen(name, mode);
    if(box->file==NULL)
    {   fprintf(stderr, "Unable to open file %s for %s.\n", name, mode);
        return obj_ref;
    }

    if(box->trace <= TRACE_PROGRESS)
        MBPC_log(box, progress,
            newSVpvf("Opened file %s with mode %s.", name, mode));

    sv_setiv(obj, (IV)box);
    SvREADONLY_on(obj);

/* fprintf(stderr, "Open is done.\n"); */
    return obj_ref;
}

void MBPC_close_file(SV *obj)
{   Mailbox   *box = GETPTR(obj);
    Separator *sep;

    if(box->file==NULL) return;   /* already closed */

    fclose(box->file);
    box->file = NULL;

    free(box->filename);

    sep = box->separators;
    while(sep!=NULL)
    {   Separator * next = sep->next;
        free(sep->line);
        free(sep);
        sep = next;
    }
}

void MBPC_struct_DESTROY(SV* obj)
{   SV      *ref = SvRV(obj);  /* carefully unpack, because order of */
    Mailbox *box;              /* DESTROY is not known.              */

    if(ref==NULL) return;

    box = SvIV(ref);
    if(box==NULL) return;

    free(box->filename);
    free(box);
}

void MBPC_push_separator(SV *obj, char *line_start)
{   Mailbox    *box = GETPTR(obj);
    Separator  *new = (Separator *)malloc(sizeof(Separator));
    if(new==NULL)
    {   fprintf(stderr, "No mem for separator-struct.\n");
        exit(errno);
    }

    new->line       = strdup(line_start);
    new->length     = strlen(line_start);
    new->next       = box->separators;
    box->separators = new;

    if(strncmp(new->line, "From ", new->length)==0)
        box->strip_gt++;
}

SV* MBPC_pop_separator(SV *obj)
{   Mailbox   *box = GETPTR(obj);
    Separator *old = box->separators;
    SV        *line;

    if(old==NULL) return NULL;

    if(strncmp(old->line, "From ", old->length)==0)
        box->strip_gt--;

    box->separators = old->next;
    line = newSVpv(old->line, old->length);
    free(old->line);
    free(old);
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

/*
 * read_header
 */

static int read_header_line(Mailbox *box, SV **field, SV **content);

void read_header(SV *obj)
{   Mailbox *box = GETPTR(obj);
    SV      *field, *content;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box->file==NULL)
        Inline_Stack_Done;                 /* returns */

    Inline_Stack_Push(sv_2mortal(newSViv(file_position(box))));

    while(read_header_line(box, &field, &content))
    {   Inline_Stack_Push(sv_2mortal(field));
        Inline_Stack_Push(sv_2mortal(content));
    }
 
    Inline_Stack_Done;
}

static int
read_header_line(Mailbox *box, SV **field, SV **content)
{
    char * line   = get_one_line(box);
    char * reader;
    int    length, field_error;

    if(line==NULL) return 0;
    if(line[0]=='\n') return 0;

    /*
     * Read the header's field.
     */

    for(reader = line; *reader != ':' && *reader!='\n'; reader++)
        ;

    if(*reader=='\n')
    {   MBPC_log(box, warning,
            newSVpvf("Unexpected end of header:\n  %s", line));

        box->keep_line = 1;
        return 0;
    }

    field_error = 0;
    for(length = reader-line; length >= 0 && line[length]==' '; --length)
        field_error++;

    if(field_error && box->trace <= TRACE_WARNINGS)
    {   MBPC_log(box, warning,
            newSVpvf("Blanks after header-fieldname:\n  %s", line));

        box->keep_line = 1;
    }

    *field = newSVpvn(line, length);

    /*
     * Now read the content.
     */

    /* skip starting blanks. */
    for(++reader; *reader=='\n' || *reader==' '; ++reader)
        ;
    line = reader;

    /* skip the text. */
    for(; *reader!='\n'; ++reader)
        ;
    *reader-- = EOL;

    /* skip trailing blanks. */
    while(*reader==' ' && reader >= line) *reader-- = EOL;

    if(reader < line && box->trace <= TRACE_NOTICES)
        MBPC_log( box, notice
                , newSVpvf( "Empty header content for field %s"
                           , SvPV_nolen(*field)));
   
    *content = newSVpvn(line, reader-line+1);

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
        *reader= EOL;
        while(*reader==' ' && reader>line) *reader-- = EOL;

        /* append stripped line. */
        sv_catpvn(*content, line, reader-line);
    }

    return 1;
}

static void MBPC_print_SV(SV *sv, FILE *out)
{   STRLEN   length;
    char   * string;
fprintf(out, "xxx.\n");
string = SvPV_nolen(sv);
    fprintf(out, "%s", string);
}

static void MBPC_log(Mailbox *box, SV *level, SV *text)
{
return;
    MBPC_print_SV(level, stderr);
    fputs(": ", stderr);
    MBPC_print_SV(text, stderr);
    putc('\n', stderr);

/* TBI
    call_perl_box->log(SvREFCNT_inc(level),
          box->msgnr, box->partnr, sv_2mortal(text));
 */
}

/*
 * fold_header_line
 * Fold an (already unfolded) line.
 */

void MBPC_fold_header_line(char *line, int maxchar)
{
    Inline_Stack_Vars;
    char copy[MAXFOLD];

    Inline_Stack_Reset;

    if(maxchar > MAXFOLD)
    {   fprintf( stderr
               , "Error: fold-size maximum too low: is %d, requires %d\n"
               , MAXFOLD, maxchar);
        exit(EINVAL);
    }

    copy[0] = EOL;
    while(1)
    {   int length;
        int c;
        int next   = 0;

        /*
         * Got to the tail?
         */

        length = strlen(line);
        if(*copy==EOL && length <= maxchar)
        {   Inline_Stack_Push(sv_2mortal(newSVpv(line, length)));
            Inline_Stack_Done;
            return;
        }
        else if(*copy!=EOL && length <= maxchar - strlen(copy))
        {   strcat(copy, line);
            Inline_Stack_Push(sv_2mortal(newSVpv(copy, strlen(copy))));
            Inline_Stack_Done;
            return;
        }

        /*
         * First try to fold on normal folding characters ',' and ';'.
         */

        for(c = maxchar - strlen(copy); c > 20; c--)
        {   if(line[c]!=',' && line[c]!=';')
                continue;

            strncat(copy, line, c+1);
            line += c + 1;
            Inline_Stack_Push(sv_2mortal(newSVpv(copy, strlen(copy))));
            strcpy(copy, FOLDSTART);

            while(*line==' ') line++;  /* skip blanks. */
            next = 1;
            break;
        }
        if(next) continue;

        /*
         * Now try to fold on less usual blank and dot.
         */

        for(c = maxchar - strlen(copy); c > 20; c--)
        {   if(line[c]!=' ' && line[c]!='.')
                continue;

            strncat(copy, line, c+1);
            line += c + 1;
            Inline_Stack_Push(sv_2mortal(newSVpv(copy, strlen(copy))));
            strcpy(copy, FOLDSTART);

            while(*line==' ') line++;  /* skip blanks. */
            next = 1;
            break;
        }
        if(next) continue;

        /*
         * If folding doesn't work, continue to read until
         * there is a character which can be folded upon.
         */

        {   int    take   = maxchar - strlen(copy);
            int    length = maxchar;

            strncat(copy, line, take);
            line += take;
            while(length < MAXFOLD)
            {   char this = copy[length++] = *line++;
                if(this==',' || this==';' || this==',' || this==' ')
                    break;
            }

            Inline_Stack_Push(sv_2mortal(newSVpv(copy, length)));
            strcpy(copy, FOLDSTART);
        }
    }

    Inline_Stack_Done;
}

/*
 * in_dosmode
 */

int MBPC_in_dosmode(SV *obj)
{   Mailbox *box = GETPTR(obj);
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

    if(where >= 0 && fseek(box->file, where, SEEK_SET)!=0)
        return 0;                 /* file too short. */

    old_location   = file_position(box);
    box->keep_line = 0;           /* carefully destroy unget-line. */

    line = get_one_line(box);     /* find first non-empty line. */
    while(line!=NULL && line[0]=='\n' && line[1]==EOL)
        line = get_one_line(box);

    found =  line==NULL || strncmp(line, sep->line, sep->length)==0;

    fseek(box->file, old_location, SEEK_SET);
    return found;
}

/*
 * read_separator
 * Return a line with the last defined separator.  Empty lines before this
 * are permitted, but no other lines.
 */

void MBPC_read_separator(SV *obj)
{   Mailbox   *box  = GETPTR(obj);
    Separator *sep  = box->separators;
    char      *line;
    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(sep==NULL)              /* Never success when there is no sep */
        Inline_Stack_Return(0);

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
    int *nr_lines,    int *nr_chars)
{   char   ** lines;
    int       max_lines;
    long      start      = file_position(box);

    max_lines  = expect_lines > 0 ? expect_lines : 1000;
    lines      = (char **)malloc(max_lines * sizeof(char *));
    if(lines==NULL)
    {   fprintf(stderr, "No mem for %d read_stripped_lines.\n", max_lines);
        exit(errno);
    }

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
        {   if(*nr_lines>0)       /* remove empty line before separator.   */
            {   char *prev = lines[*nr_lines -1];
                if(prev[0]=='\n' && prev[1]==EOL)
                    (*nr_lines)--;
                free(prev);
            }
            break;
        }

        if(*nr_lines >= max_lines)
        {   max_lines += max_lines;
            lines = realloc(lines, max_lines * sizeof(char *));
            if(lines==NULL)
            {   fprintf(stderr, "No mem for %d stripped lines.\n", max_lines);
                exit(errno);
            }
        }

        /*
         * Check for separator
         */

        sep = box->separators;
        while(sep != NULL && strncmp(sep->line, line, sep->length)!=0)
            sep = sep->next;

        if(sep!=NULL)
        {   /* Separtor found */
            box->keep_line = 1;   /* keep separator line to be read later. */
            if(*nr_lines>0)       /* remove empty line before separator.   */
            {   char *prev = lines[*nr_lines -1];
                if(prev[0]=='\n' && prev[1]==EOL)
                    (*nr_lines)--;
                free(prev);
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

        lines[(*nr_lines)++] = strdup(line);
        *nr_chars           += strlen(line);
    }


    return lines;
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
{   Mailbox *box    = GETPTR(obj);
    SV      *result;
    char   **lines;
    int      nr_lines, nr_chars, line_nr;
    long     begin  = file_position(box);

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(!box->dosmode && !box->strip_gt && expect_chars >=0)
    {
        long  end    = begin + expect_chars;

        if(is_good_end(box, end))
        {   Inline_Stack_Push(sv_2mortal(newSViv(begin)));
            Inline_Stack_Push(sv_2mortal(take_scalar(box, begin, end)));
            Inline_Stack_Return(2);
        }
    }

    lines = read_stripped_lines(box, expect_chars, expect_lines,
        &nr_lines, &nr_chars);

    if(lines==NULL)
        Inline_Stack_Return(0);

    /* Join the strings. */
    result = newSVpv("",0);
    SvGROW(result, nr_chars);

    for(line_nr=0; line_nr<nr_lines; line_nr++)
    {   sv_catpv(result, lines[line_nr]);
        free(lines[line_nr]);
    }

    free(lines);

    Inline_Stack_Push(sv_2mortal(newSViv(begin)));
    Inline_Stack_Push(sv_2mortal(result));
    Inline_Stack_Return(2);
}

/*
 * body_as_list
 * Read the whole body into a list of scalars.
 */

void MBPC_body_as_list(SV *obj, int expect_chars, int expect_lines)
{   Mailbox *box    = GETPTR(obj);
    char   **lines;
    int      nr_lines, nr_chars, line_nr;
    Inline_Stack_Vars;
    Inline_Stack_Reset;

    lines = read_stripped_lines(box, expect_chars, expect_lines,
        &nr_lines, &nr_chars);

    if(lines==NULL)
        Inline_Stack_Return(0);

    Inline_Stack_Push(sv_2mortal(newSViv(file_position(box))));

    /* Join the strings. */

    for(line_nr=0; line_nr<nr_lines; line_nr++)
    {   char *line = lines[line_nr];
        Inline_Stack_Push(sv_2mortal(newSVpv(line, strlen(line))));
        free(line);
    }

    free(lines);
    Inline_Stack_Done;
}
