# Author:  <wblake@CB95043>
# Created: Aug 26, 2025
# Version: 0.01
#
# Usage: perl [-d] [-r ] [-x] [-g] patronBouncedEmail.pl filename.csv
# -d Debug/verbose 
# -g Logging
# -x don't send email
# filename.csv has Patron barcode, Patron Point Bounce Result
# Input file filename.csv should only have existing Patron Records
#$patronid,$PPBouncedResult
# Note that Allow Email needs an email address in the patron record to "stick."
#Debug mode- a lot more SOAP messages.
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for PatronAPI requests
#
# SOAPUI tool can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
# An SQL Query to select patrons from an imported table PPBOUNCED
#select distinct patron.patronid, bounce."DNC Reason",upper(patron.email),upper(bounce.email) as bounceemail,
#        case emailnotices when 0 then 'No Email Notices'
#                          when 1 then 'Email Notices'
#                          when 2 then 'bounced email'
#                          when 3 then 'opt out'
#                          else 'Unknown' end as emailnotices,
#        bty.btycode, name from patron_v2 patron
# inner join bty_v2 bty on (patron.bty = bty.btynumber)

# inner join ppbounced bounce
#     on substr(upper(patron.email),1, 10) = substr(upper(bounce.email),1,10)  ;

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

use constant BOUNCETYPE_SOFT_BOUNCE => 'S';
use constant BOUNCETYPE_HARD_BOUNCE => 'H';

use constant EMAIL_NOTICE_SEND_EMAIL => 'send email' ;
use constant EMAIL_NOTICE_BOUNCED_EMAIL => 'bounced email' ;
use constant EMAIL_NOTICE_OPTOUT => 'opted out' ;
use constant EMAIL_NOTICE_NO_EMAIL => 'do not send email' ;

use constant BOUNCED_EMAIL_NOTE_TYPE => 900;
use constant INFO_NOTE_TYPE => 501;

use constant BOUNCED_EMAIL_SOFT_NOTE_TEXT => "Patron Point Soft Email Bounce";
use constant BOUNCED_EMAIL_HARD_NOTE_TEXT => "Patron Point Hard Email Bounce";

#Command line input variable handling
our ($opt_g,$opt_r,$opt_x);
getopts('grx');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $PATRON_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

#INFO "[$local_filename" . ":" . __LINE__ . "]$PATRON_FILE";

#See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/
my $wsdlfile = 'PatronAPInew.wsdl';

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('UpdatePatron');
my $call2 = $wsdl->compileClient('AddPatronNote');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1\n" ;
}


my ($patronid,$birthdate,$bouncetype) ;

my %PatronRequest;
my %PatronUpdateValues = ( PatronStatusCode => 'S' );
my %PatronUpdateRequest;
my %AddNote =( NoteType => BOUNCED_EMAIL_NOTE_TYPE , NoteText => BOUNCED_EMAIL_HARD_NOTE_TEXT);


%PatronUpdateRequest =
       (
        SearchType => SEARCHTYPE_PATRONID,
        Patron => \%PatronUpdateValues,
        Modifiers=> {
        DebugMode=>1,
        ReportMode=>1}
       );

# INFO "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;

my %AddNoteRequest;

 
    %AddNoteRequest =
      (
       Note => \%AddNote,
       Modifiers => {
		     DebugMode => 1,
		     ReportMode => 1
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

my $softOrHardBounce=BOUNCETYPE_SOFT_BOUNCE;

# Loop until the end of the input file with the first line an assumed header.

mce_loop_f {

  chomp;
  # INFO "[$local_filename" . ":" . __LINE__ . "]Record $_";

  # Expect only the patronid in the simplest input file.
  #        ($patronid, $name,$bty,$email)  = split(/,/);

  $softOrHardBounce=BOUNCETYPE_SOFT_BOUNCE;
  
  ($patronid,$birthdate,$bouncetype)  = split(/,/);

  next if $patronid !~/\d{5,}/;

  my @patterns = map { qr/\b$_\b/i } qw( spam preblocked );
  
   foreach my $pattern ( @patterns ) {
       if( $bouncetype =~ m/$pattern/ ) {
	   $softOrHardBounce=BOUNCETYPE_HARD_BOUNCE;
	   last ;
       }
     
   }
  INFO "[$local_filename" . ":" . __LINE__ . "]bouncetype $bouncetype";	    	    

  %PatronUpdateValues = ( EmailNotices => ($softOrHardBounce eq BOUNCETYPE_SOFT_BOUNCE )? EMAIL_NOTICE_BOUNCED_EMAIL:EMAIL_NOTICE_OPTOUT,
			BirthDate => $birthdate
			) ; 

  INFO "[$local_filename" . ":" . __LINE__ . "]PatronUpdateValues " . Dumper(\%PatronUpdateValues) ;
  
  $PatronUpdateRequest{SearchID}= $patronid;

 INFO "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;

  my ($result1,$trace1)=$call1->(%PatronUpdateRequest);

  if ($trace1->errors) {
      $trace1->printErrors;

  }
  
  # Add Patron Note for Hard Bounce

  if ( $softOrHardBounce eq BOUNCETYPE_HARD_BOUNCE){
      $AddNote{PatronID} = $patronid;
      my ($result2,$trace2)=$call2->(%AddNoteRequest);
      if ($trace1->errors) {
	  $trace1->printErrors;
      }
  }
  
} $PATRON_FILE ;

MCE::Loop::finish;
