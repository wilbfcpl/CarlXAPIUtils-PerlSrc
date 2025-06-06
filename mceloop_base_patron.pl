
# Author:  <wblake@CB95043>
# Created: Feb 16, 2023
# Version: 0.01
#
# Usage: perl [-d] [-r ] [-x] [-g] patronAllowEmail.pl filename.csv
# -d Debug/verbose 
# -g Logging
# -x don't send email
# filename.csv is a file  with Patron barcode, borrower name, borrower type, and email address
# Input file filename.csv should only have existing Patron Records
#$patronid,$name,$bty,$email
#Debug mode- a lot more SOAP messages.
# Assumes first line of in file has column label headings
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for interface to PatronAPI requests AddPatronNote
#
# A tool like SOAPUI can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
# An SQL Query to select patrons from an imported table PATRONSDONOTSENDEMAIL
#select sample.name, sample.email, patron.emailnotices from carlreports.PATRONSDONOTSENDEMAIL sample, carlreports.PATRON_V2 patron
#where sample.patronid = patron.patronid order by sample.name;

use strict;
use warnings FATAL => 'all';
use diagnostics;

use LWP::UserAgent;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;
use Data::Dumper;
use Getopt::Std;
use integer;
use MCE::Loop;  # Import the MCE::Loop module
use feature 'say';
use Log::Log4perl qw(:easy);
use IO::Prompt::Tiny qw/prompt/;

#TRACE,DEBUG,INFO,WARN,ERROR,FATAL
Log::Log4perl->easy_init($TRACE);
# Reduce number of magic values where possible
use constant SEARCHTYPE_PATRONID => 'Patron ID';
use constant EMAIL_NOTICE_SEND_EMAIL => 'send email' ;
use constant EMAIL_NOTICE_NO_EMAIL => 'do not send email' ;

#Command line input variable handling
our ($opt_g,$opt_r,$opt_x);
getopts('grx:');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $PATRON_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

my ($patronid,$name,$bty,$email) ;

my %PatronRequest;
my %PatronUpdateValues;
my %PatronUpdateRequest;


%PatronUpdateRequest =
       (
        SearchType => SEARCHTYPE_PATRONID,
        Patron => \%PatronUpdateValues,
        Modifiers=> {
        DebugMode=>1,
        ReportMode=>1,}
       );


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

  # Expect only the patronid in the simplest input file.
    #        ($patronid, $name,$bty,$email)  = split(/,/);
  ($patronid)  = split(/,/);

  $PatronUpdateRequest{SearchID}= $patronid;
  
  my ($result1,$trace1)=$call1->(%PatronUpdateRequest);

  if ($trace1->errors) {
    $trace1->printErrors;
  }
} $PATRON_FILE ;

MCE::Loop::finish;


