package Mail::Box::Parser;

use strict;
use warnings;

our $VERSION = '2.00_00';

=head1 NAME

Mail::Box::Parser - Reading and writing messages

=head1 SYNOPSIS

=head1 DESCRIPTION

The Mail::Box::Parser package is part of the Mail::Box suite, which is
capable of parsing folders.  Usually, you won't need to know anything
about this module, except the options which are involved with this code.

A large part of this module is implemented in C, purely for performance
reasons.

=over 4

=cut

#------------------------------------------

=item openFile

Start reading from file to get one message (in case of MH-type folders)
or a list of messages (in case of MBox-type folders)

Options:

=over 4

=item * filename =E<gt> FILENAME

(obligatory) The name of the file to be read.

=item * mode =E<gt> OPENMODE

File-open mode, as accepted by the perl's C<open()> command.  Defaults to
C<'r'>, which means `read-only'.

=item * seperator =E<gt> 'FROM' | undef

Specifies whether we do expect a list of messages in this file (and in
that case in what way they are seperated), or a single message.

C<FROM> should be used for MBox-like folders, where each message
is preluded by a line starting with 'From '.  Typical lines are

   From wouter Tue May 19 15:59 MET 1998
   From piet@example.com Tue May 19 15:59 MET 1998 -0100
   From me@example.nl 19 Mei 2000 GMT

Message-bodies which accidentally contain lines starting with 'From'
must be escaped, however not all application are careful enough.  This
module does use other heuristics to filter these failures out.

Specify C<undef> if there are no seperators to be expected, because
you have only one message per folder, like in MH-like mail-folders.

=item * trace =E<gt> LEVEL

Which level of message shall be shown directly when they occur.  As LEVEL
you can give ERRORS, WARNINGS, PROGRESS, NOTICE, DEBUG, or NONE, specifying
the lowest importance of the messages to be shown.

The error and warning messages are also stored in the message object
in which those messages occur.

=item * fold =E<gt> INTEGER

(folder writing only) Automatic fold headerlines larger than this
specified value.  Disabled when set to zero.

=item * dosmode =E<gt> BOOLEAN

(unix writing only) specifies whether the folder-file must be
written with a CRLF between lines, instead of the usual LF-only.
This is required when the unix system handles Windows folders.

For reading of folders, this is autodetected.

=back

=cut

sub openFile(@)
{   my ($class, %args) = @_;

    my $mode    = $args{mode} || 'r';
    my $dosmode = defined $args{dosmode} ? $args{dosmode}
                : $mode =~ /r/           ? 1
                :                          0;
    my $fold    = defined $args{fold} ? $args{fold} : 72;

    open_file(__PACKAGE__, $args{filename}
       , Mail::Error->logPriority($args{trace}||'WARNING')
       , $mode, $fold, $dosmode, $args{seperator} || 0
       );
}

#------------------------------------------

use Inline C => Config
         , NAME => 'Mail::Box::Parser'
         , PREFIX  => 'MBP_';
use Inline C => 'DATA';
Inline->init;



#------------------------------------------

=back

=head1 AUTHORS

Mark Overmeer <mark@overmeer.net>

=head1 VERSION

This code is beta version 2.00_00.
Please contribute with remarks and additions.

=head1 COPYRIGHT

Copyright (c) 2001 Mark Overmeer and David Coppit. All rights reserved.
This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

__DATA__
__C__

#define NO_TRACE        6  /* synchronize this with the %trace_levels */
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
    int        dosmode;
    int        trace;

    int        current_msgnr;
    int        current_partnr;

    char       line[MAX_LINE];
    int        keep_line;      /* unget line */
} Mailbox;

static SV *notice, *progress, *warning, *error;
static void MBP_log(Mailbox *box, SV *level, SV *text);

void init()
{
    Inline_Stack_Vars;
    error    = newSVpv("ERROR",    5);
    warning  = newSVpv("WARNING",  7);
    progress = newSVpv("PROGRESS", 8);
    notice   = newSVpv("NOTICE",   6);
    Inline_Stack_Void;
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

SV *MBP_open_file(char *class, char *name, int trace, char *mode,
    int fold_length, int dosmode, int with_from_line)
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

    /* Dosmode will strip/add \r before each \n, and is required when
     * processing Windows folder under UNIX.  The flag is turned on
     * when reading, but automatically switched off when the first line
     * does not have a \r.
     */
    box->dosmode      = dosmode;

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
        MBP_log(box, progress,
            newSVpvf("Opened file %s with mode %s.", name, mode));

    sv_setiv(obj, (IV)box);
    SvREADONLY_on(obj);
    return obj_ref;
}

void MBP_close(SV *obj)
{   Mailbox *box = GETPTR(obj);
    if(box->file==NULL) return;

    if(box->trace <= TRACE_PROGRESS)
        MBP_log(box, progress, newSVpvf("File %s closed.", box->filename));

    fclose(box->file);
    box->file = NULL;
}

void MBP_DESTROY(SV* obj)
{   Mailbox *box = GETPTR(obj);
    MBP_close(obj);

    if(box->trace <= TRACE_PROGRESS)
        MBP_log(box, progress, newSVpvf("File %s destroyed.", box->filename));

    free(box->filename);
}

int MBP_linenr(SV* obj)
{   return GETPTR(obj)->linenr;
}

int MBP_dosmode(SV* obj)
{   return GETPTR(obj)->dosmode;
}

static char * MBP_getline(Mailbox *box)
{
    if(box->keep_line)
    {   box->keep_line = 0;
        return box->line;
    }

    if(!fgets(box->line, MAX_LINE, box->file))
        return NULL;

    box->linenr++;
    if(box->dosmode)
    {   int length = strlen(box->line);
        if(length>=2 && box->line[length-2]=='\r')
        {   /* Remove \r before \n, it will be restored on write
             * when the receiving folder has been opened in dosmode.
             */
            box->line[--length] = '\0';
            box->line[length-1] = '\n';
        }
        else
        {   /* Reading in dosmode is not needed, because this
             * line doesn't end with \r\n; dosmode switched off
             */
             box->dosmode = 0;
        }
    }

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

static int MBP_read_header_line(Mailbox *box, SV **field, SV **content);

void read_header(SV *obj)
{   Mailbox *box = GETPTR(obj);
    SV      *field, *content;

    Inline_Stack_Vars;
    Inline_Stack_Reset;

    if(box->file==NULL)
        Inline_Stack_Done;                 /* returns */

    if(box->take_fromline)
    {   char *from = MBP_getline(box);
        if(from==NULL) Inline_Stack_Done;

        Inline_Stack_Push(newSVpv(from, strlen(from)));
    }
    else
    {   Inline_Stack_Push(&PL_sv_undef);
    }

    while(MBP_read_header_line(box, &field, &content))
    {   Inline_Stack_Push(sv_2mortal(field));
        Inline_Stack_Push(sv_2mortal(content));
    }
 
    Inline_Stack_Done;
}

static int MBP_read_header_line(Mailbox *box, SV **field, SV **content)
{
    char * line   = MBP_getline(box);
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
    {   MBP_log(box, warning,
            newSVpvf("Unexpected end of header in line %d:\n  %s",
                      box->linenr, line));

        box->keep_line = 1;
        return 0;
    }

    field_error = 0;
    for(length = reader-line; length >= 0 && line[length]==' '; --length)
        field_error++;

    if(field_error && box->trace <= TRACE_WARNINGS)
    {   MBP_log(box, warning,
            newSVpvf("Blanks after header-fieldname in line %d:\n  %s",
                     box->linenr, line));

        box->keep_line = 1;
    }

    *field = newSVpvn(line, length);

    /*
     * Now read the content.
     */

    /* skip starting blanks. */
    for(++reader; *reader!='\n' && *reader!=' '; ++reader)
        ;
    line = reader;

    /* skip the text. */
    for(; *reader!='\n'; ++reader)
        ;
    *reader-- = EOL;

    /* skip trailing blanks. */
    while(*reader==' ' && reader >= line) *reader-- = EOL;

    if(reader < line && box->trace <= TRACE_NOTICES)
        MBP_log(box, notice,
                newSVpvf("Empty header content in line %d for field %s"
                        , box->linenr, SvPV_nolen(*field)));
   
    *content = newSVpvn(line, reader-line+1);

    /*
     * Let's do some unfolding.  We read a line more, which may
     * be not related to this one... but happily it can be unget.
     */

    while(1)
    {   line     = MBP_getline(box);
        if(line[0]!=' ')
        {   box->keep_line = 1;
            break;
        }

        /* skip all but one blank. */
        while(line[1]==' ') line++;

        /* strip blanks at end of line. */
        reader = line+strlen(line)-1;
        *reader= EOL;
        while(*reader==' ' && reader>line) *reader-- = EOL;

        /* append stripped line. */
        sv_catpvn(*content, line, reader-line);
    }

    return 1;
}

static void MBP_print_SV(SV *sv, FILE *out)
{   STRLEN   length;
    char   * string;
fprintf(out, "xxx.\n");
string = SvPV(sv, length);
fprintf(out, "length = %ld.\n", length);
    fprintf(out, "%*s", length, string);
}

static void MBP_log(Mailbox *box, SV *level, SV *text)
{
    MBP_print_SV(level, stderr);
    fputs(": ", stderr);
    MBP_print_SV(text, stderr);
    putc('\n', stderr);

/* TBI
    call_perl_box->log(SvREFCNT_inc(level),
          box->msgnr, box->partnr, sv_2mortal(text));
 */
}

void MBP_fold_header_line(char *line, int maxchar)
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

fprintf(stderr, "Done");
    Inline_Stack_Done;
}
