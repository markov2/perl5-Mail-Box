use strict;
use warnings;

package Mail::Box::Parser::C;
use base 'Mail::Box::Parser';

# Parse mail-boxes in C.  See Mail::Box::Parser
#
# Copyright (c) 2001 Mark Overmeer. All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

our $VERSION = '2.00_01';

use Inline C       => 'DATA'
          , NAME   => 'Mail::Box::Parser::C'
          , PREFIX => 'MBPC_';

Inline->init;

init_log_labels();

#------------------------------------------

sub init(@)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    my $r = open_file( __PACKAGE__
       , $args->{filename}
       , $self->logPriority($args->{trace})
       , $args->{mode}, $args->{fold}
       , $args->{seperator} eq 'FROM'
       );
warn "Came back with $r";
    $r;
}

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

#define MAXFOLD        512
#define FOLDSTART      "        "

#define GETPTR(OBJECT) ((Mailbox *)SvIV(SvRV(OBJECT)))

typedef struct
{   char     * filename;
    FILE     * file;

    int        linenr;
    int        fold_length;
    int        take_fromline;
    int        trace;

    int        current_msgnr;
    int        current_partnr;

    char       line[MAX_LINE];
    int        keep_line;      /* unget line */
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
 * Inline::C-Cookbook manualpage.
 */

SV *MBPC_open_file(char *class, char *name, int trace, char *mode,
    int fold_length, int with_from_line)
{
    Mailbox * box     = (Mailbox *)malloc(sizeof(Mailbox));
    SV      * obj_ref = newSViv(0);
    SV      * obj     = newSVrv(obj_ref, class);

    if(box==NULL)
    {   fprintf(stderr, "Out of memory for mailbox structure %s.\n", name);
        return NULL;
    }

    box->linenr       = 0;
    box->keep_line    = 0;
    box->fold_length  = fold_length;
    box->take_fromline= with_from_line;

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

fprintf(stderr, "Open is done.\n");
    return obj_ref;
}

void MBPC_close(SV *obj)
{   Mailbox *box = GETPTR(obj);
    if(box->file==NULL) return;

    if(box->trace <= TRACE_PROGRESS)
        MBPC_log(box, progress, newSVpvf("File %s closed.", box->filename));

    fclose(box->file);
    box->file = NULL;
}

void MBPC_DESTROY(SV* obj)
{   Mailbox *box = GETPTR(obj);
    MBPC_close(obj);

    if(box->trace <= TRACE_PROGRESS)
        MBPC_log(box, progress, newSVpvf("File %s destroyed.", box->filename));

    free(box->filename);
}

int MBPC_linenr(SV* obj)
{   return GETPTR(obj)->linenr;
}

static char * MBPC_getline(Mailbox *box)
{
    if(box->keep_line)
    {   box->keep_line = 0;
        return box->line;
    }

    if(!fgets(box->line, MAX_LINE, box->file))
        return NULL;

    box->linenr++;

    return box->line;
}

/*
 * READ_HEADER
 *
 * Read the whole message-header, and return it as list, which
 * are field => value, field => value.  Mind that some fields
 * will appear more than once.
 *
 * Returns to perl a list.  The first value is the `From '-line
 * (when defined for this folder-type, see the `with_from_line'
 * parameter to open_file).  Then you get a list of beautified
 * header-fields, each in key-value couples.
 * If there are no elements returned, end of file is reached.
 */

static int MBPC_read_header_line(Mailbox *box, SV **field, SV **content);

void read_header(SV *obj)
{   Mailbox *box = GETPTR(obj);
    SV      *field, *content;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box->file==NULL)
        Inline_Stack_Done;                 /* returns */

    if(box->take_fromline)
    {   char *from = MBPC_getline(box);
        if(from==NULL) Inline_Stack_Done;
        Inline_Stack_Push(newSVpv(from, strlen(from)));
    }
    else
    {   Inline_Stack_Push(&PL_sv_undef);
    }

    while(MBPC_read_header_line(box, &field, &content))
    {   Inline_Stack_Push(sv_2mortal(field));
        Inline_Stack_Push(sv_2mortal(content));
    }
 
    Inline_Stack_Done;
}

static int MBPC_read_header_line(Mailbox *box, SV **field, SV **content)
{
    char * line   = MBPC_getline(box);
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
            newSVpvf("Unexpected end of header in line %d:\n  %s",
                      box->linenr, line));

        box->keep_line = 1;
        return 0;
    }

    field_error = 0;
    for(length = reader-line; length >= 0 && line[length]==' '; --length)
        field_error++;

    if(field_error && box->trace <= TRACE_WARNINGS)
    {   MBPC_log(box, warning,
            newSVpvf("Blanks after header-fieldname in line %d:\n  %s",
                     box->linenr, line));

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
        MBPC_log(box, notice,
                newSVpvf("Empty header content in line %d for field %s"
                        , box->linenr, SvPV_nolen(*field)));
   
    *content = newSVpvn(line, reader-line+1);

    /*
     * Let's do some unfolding.  We read a line more, which may
     * be not related to this one... but happily it can be unget.
     */

    while(1)
    {   line     = MBPC_getline(box);
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
 * foldHeaderLine
 * Called directly by other modules
 */

void MBPC_foldHeaderLine(char *class, char *line, int maxchar)
{
    Inline_Stack_Vars;
    int  line_nr = 0;
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
