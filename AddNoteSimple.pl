# Author:  <wblake@CB95043>
# Created: Feb 16, 2023
# Version: 0.01
#
# Usage: perl [-d] AddNoteMCE.pl [-r ] [-x] [-g] filename.csv
# -d Debug/verbose captured by perl exe, remaining options left for this script
# -g Logging
# checked but not used: -r, -x
# filename.csv is a file  with FCPS Student information for their FCPL Student Success Card Account
# Warning.
# Input file filename.csv should only have Students that have Soft-Block status.
# fcpsAddNote_min.pl will add a Note to every account listed.
# Only the patronid column really matters but the Input CSV file column order goes:
# patronid, $name,$status,$btycode,$street1,$notes,$regdate,$editdate,$actdate
#
#Debug mode- a lot more SOAP messages.=
#
# Assumes first line of in file has column label headings
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for interface to PatronAPI requests AddPatronNote
#
# A tool like SOAPUI can provide a sandbox for the WSDL file and PatronAPI requests.
#
# Note that API call and response return appear to take one second in real time.
# 
# An SQL Query to select updated Student Patron records
#select student.patronid, student.name, status, BTYCODE, student.STREET1,notes,trunc(regdate),trunc(editdate),trunc(actdate)
#expected csv file columns:   
#$patronid, $name,$status,$btycode,$street1,$notes,$regdate,$editdate,$actdate
# select patronid, name, bty, regdate from patron_v2 where bty=10 and regdate>'20-JAN-22';
#

use strict;
use warnings FATAL => 'all';
use diagnostics;

# See CPAN, web pages XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Transport::SOAPHTTP;
use Data::Dumper;
use Getopt::Std;
use integer;

use MCE::Loop;  # Import the MCE::Loop module
use Data::Dumper;
use feature 'say';
use Log::Log4perl qw(:easy);

#TRACE,DEBUG,INFO,WARN,ERROR,FATAL
Log::Log4perl->easy_init($TRACE);
# Reduce number of magic values where possible
use constant WITHDRAW_SOFTBLOCK_NOTE_TEXT => 'Student withdrawn from school system - Create / Check for PUBLIC or CHILD Card';
use constant GRAD_SOFTBLOCK_NOTE_TEXT => 'Graduated student - Create / Check for PUBLIC card' ;
use constant BIRTHDAY_CONFIRM_NOTE_TEXT => 'Verify Birthdate.' ;
#use constant GRAD_SOFTBLOCK_NOTE_TYPE => 930;
use constant GRAD_SOFTBLOCK_NOTE_TYPE => 2;
use constant WITHDRAW_SOFTBLOCK_NOTE_TYPE => 2;
use constant INFO_NOTE_TYPE => 501;

#Command line input variable handling
our ($opt_g,$opt_r,$opt_x);
getopts('gdrx:');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
# Local filename is the name of this script

my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

#PATRONID_FILE is the input file having the PatronIDs for the note
my $PATRONID_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$PATRONID_FILE";

#See the CPAN,web XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
my $wsdlfile = 'PatronAPInew.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('AddPatronNote');
 
unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}

my ($patronid, $noteid, $name ,$btype, $notedate, $notetype,  $branch,$actdate, $lastbranch, $alias);

my %AddNote;
my %AddNoteRequest;

 
    %AddNoteRequest =
      (
       Note => \%AddNote,
       Modifiers => {
		     DebugMode => 1,
		     ReportMode => 1,
		    }
      ) ;



# Use MCE::Loop to process lines in parallel
 MCE::Loop::init(
    max_workers => 8,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
       );

# Loop until the end of the input file with the first line an assumed header.

mce_loop_f {

  chomp;
  INFO "[$local_filename" . ":" . __LINE__ . "]Record $_";


  ($patronid, $noteid, $name, $btype, $notedate, $notetype,$branch,$actdate, $lastbranch, $alias)=split(/,/);

   %AddNote = ($btype eq "STUDNT")?
           ( NoteType => WITHDRAW_SOFTBLOCK_NOTE_TYPE,
	     NoteText => WITHDRAW_SOFTBLOCK_NOTE_TEXT,
	   ):
            ( NoteType => GRAD_SOFTBLOCK_NOTE_TYPE,
	     NoteText => GRAD_SOFTBLOCK_NOTE_TEXT,
	   ) ;
  
    $AddNote{PatronID}= $patronid;
  
  my ($result1,$trace1)=$call1->(%AddNoteRequest);
  if ($trace1->errors) {
    $trace1->printErrors;
  }
} $PATRONID_FILE ;

MCE::Loop::finish;


