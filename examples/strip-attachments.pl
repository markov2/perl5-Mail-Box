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
# NOTE: In this version the attachments are still encoded. You can decode
#       these using the UNIX 'uudeview' utility.
#
# By Pjotr Prins <pjotr@pckassa.com>, $Date: 2002/11/30 12:14:01 $
#
# This code can be used and modified without restriction.
# Code based on example by Mark Overmeer, <mailbox@overmeer.net>, 9 nov 2001

use warnings;
use strict;
use lib '..', '.';

use Mail::Box::Manager 2.00;

my $ATTACHMENTS='attachments';

#
# Get the command line arguments.
#

die "Usage: $0 folderfile\n"
    unless @ARGV==1;

my $filename = shift @ARGV;

#
# Create Attachments directory if non existent
#

mkdir $ATTACHMENTS if (! -d $ATTACHMENTS);

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

# die "File $outfilename exists!" if (-e $outfilename);

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

    # ---- Test for large attachments
    if ($m->isMultipart)
      {
        foreach my $part ($m->parts)
	  {
             # Strip attachments larger than 16K. Another example would be:
             #   if ($part->body->mimeType ne 'text/plain')

             if ($part->body->size > 16384)
	       {
                  print "\n**** Stripping Attachment "; # ,$part->head,"\n";
                  $part->head =~ /name=\"(.+)\"/g;
                  my $disp     = $part->body->disposition;
                  my $filename = $disp->attribute('filename')
                              || $disp->attribute('name');

                  my $attachment = "$ATTACHMENTS/$filename";
                  print $attachment,"\n";
                  if (! -f $attachment)
		  {
                    # ---- Write attachment to file
                    open(FH, ">$attachment.enc");
                    print FH $part->decoded;
                    close(FH);
                  }
                  $part->delete;
	       }
	  }
      }
    $outbox->addMessage($m);
}

$mgr->closeAllFolders;
