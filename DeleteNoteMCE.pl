# Author:  <wblake@CB95043>
# Created: April 7, 2025
# Version: 0.01
#
# Usage: perl [-d] DeleteNoteMCE.pl [-r ] [-x] [-g] filename.csv
# -d Debug/verbose captured by perl exe, remaining options left for this script
# -g Logging
# checked but not used: -r, -x
#
# filename.csv is a file with no header row and every record having a Noteid,
# the id for a CarlX Note record used in the PATRONNOTETEXT table
#
# Warning.
# Input file filename.csv should have no header row (for Perl MCE) columns
# $patronid,$noteid,$timestamp, $notetype, $alias
# DeleteNoteMCE.pl will 
# Input CSV file $NOTEID_FILE columns:
# $patronid,$noteid,$timestamp, $notetype, $alias
#
#Debug mode- a lot more SOAP messages.
#
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for PatronAPI request DeletePatronNote
#
# A tool like SOAPUI can provide a sandbox for the WSDL file and PatronAPI requests.
#
# Note that API call and response return appear to take one second in real time.
# Perl MCE module can send multiple requests at the same time to offset latency.
#
#expected input csv file columns:
# $patronid,$noteid,$timestamp, $notetype, $alias
#

use strict;
use warnings FATAL => 'all';
use diagnostics;

# See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
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
Log::Log4perl->easy_init($ERROR);

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

#$NOTEID_FILE is the input file having the noteids for deletion
my $NOTEID_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

INFO "[$local_filename" . ":" . __LINE__ . "]$NOTEID_FILE";
             
#See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
my $wsdlfile = 'PatronAPInew.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('DeletePatronNote');
 
unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}
    
    my ($patronid, $noteid, $notetype, $alias, $timestamp);
    

    # Delete Patron Note
    
    my %DeleteNoteRequest;
   
  %DeleteNoteRequest =
	(
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

  ($patronid,$noteid,$timestamp, $notetype, $alias)  = split(/,/);
  
  $DeleteNoteRequest{NoteID}= $noteid;
  
  my ($result1,$trace1)=$call1->(%DeleteNoteRequest);
  if ($trace1->errors) {
    $trace1->printErrors;
  }
} $NOTEID_FILE ;

MCE::Loop::finish;
