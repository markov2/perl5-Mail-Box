#!/usr/bin/perl
#
# $Id: strip-attachments.pl,v 1.4 2002/11/30 12:14:01 wrk Exp $
#
# Strip attachments using Mail::Box module.
#
# Usage:
#
#   perl strip-attachments.pl mbox
#
# This script reads a mailbox ($ARG1) and writes attachments larger than
# 16K to a folder (./attachments/). Next it deletes the attachment from
# the E-mail and writes it to a file named $ARG1.stripped.
#
# By Pjotr Prins <pjotr@pckassa.com>, $Date: 2002/11/30 12:14:01 $
#
# This code can be used and modified without restriction.
# Code based on example by Mark Overmeer, <mailbox@overmeer.net>, 9 nov 2001

# In this example, the stripped data is written to a different folder.
# You may not need that (but please be careful: test your script well!)
# Simply remove everything related to $outbox and $outfilename, and open
# the source folder with access => 'rw'

# You may want to have a look at Mail::Message::Convert::Rebuild, which
# the provides the $msg->rebuild() method.

# BE WARNED: when different messages specify the same filename for a part,
# they will overwrite another... you may want a message sequency number in
# the path of the output file.

use warnings;
use strict;
use lib '..', '.';

use Mail::Box::Manager;    # everything else will auto-compile when used

use File::Basename 'basename';
use File::Spec;

my $attachments = 'attachments';

#
# Get the command line arguments.
#

die "Usage: $0 folderfile\n"
    unless @ARGV==1;

my $filename = shift @ARGV;

#
# Create Attachments directory if non existent
#

   -d $attachments
or mkdir $attachments
or die "Cannot create directory $attachments\n";

#
# Open the folders
#

my $mgr    = Mail::Box::Manager->new;
my $folder = $mgr->open
   ( $filename
   , extract    => 'LAZY'   # never take the body unless needed
   );                       #  which saves memory and time.

die "Cannot open $filename: $!\n"
    unless defined $folder;

my $outfilename = "$filename.stripped";
# die "File $outfilename exists!" if -e $outfilename;

my $outbox = $mgr->open
  ( $outfilename
  , access   => 'a'        # append,
  , create   => 1          # create if not existent
  );

die "Cannot open $outfilename to write: $!\n"
    unless defined $outbox;

my @messages = $folder->messages;
print "Mail folder $filename contains ", scalar @messages, " messages:\n";

my $counter  = 1;
foreach my $message (@messages)
{   printf "%3d. ", $counter++;
    print $message->get('Subject') || '<no subject>', "\n";

    $message->printStructure;
    my $m = $message->clone;

    unless($m->isMultipart)
    {   $outbox->addMessage($m);
        next;
    }

    foreach my $part ($m->parts)
    {
         # Strip attachments larger than 16K. Another example would be:
         #   if ($part->body->mimeType ne 'text/plain')
         next unless $part->body->size > 16384;

         print "\n**** Stripping Attachment "; # ,$part->head,"\n";
         my $disp     = $part->body->disposition;
         my $name     = $disp->attribute('filename')
                     || $disp->attribute('name');

         # a major security hole if you accept any path!
         $filename    = basename $name;

         my $attachment = File::Spec->catfile($attachments, $filename);
         print $attachment,"\n";

         unless(-f $attachment)     #  Write attachment to file
         {   open(FH, ">$attachment");
             $part->decoded->print(\*FH);
             close(FH);
         }

         $part->delete;
    }

    $outbox->addMessage($m);
}

$mgr->closeAllFolders;
