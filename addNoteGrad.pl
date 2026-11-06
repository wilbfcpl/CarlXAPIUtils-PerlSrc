# Author:  <wblake@CB95043>
# Created: Feb 16, 2023
# Version: 0.02
#
# Usage: perl [-d] AddNoteGrad.pl [-p ] [-w] [-g] filename.csv
# echo "11982021684457" |  perl addNoteGrad.pl -g
# -g Log Level as TRACE,DEBUG,INFO,WARN,ERROR,FATAL
# -p PRODUCTION SERVER update mode- BE CAREFUL and BE SURE
# -w for Withdrawn student note instead of Graduated
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
our ($opt_g,$opt_p,$opt_w);
getopts('gpw');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
# Local filename is the name of this script

my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

my $wsdlurl = ( defined $opt_p ? 'http://fcplapp.fcpl.org:8080/CarlXAPI/PatronAPI.wsdl' : 'http://fcplapp.fcpl.org:8081/CarlXAPI/PatronAPI.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlurl: $wsdlurl";

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

# Fetch the WSDL document as raw bytes. ->content rather than ->decoded_content is
# deliberate: the document carries its own <?xml ... encoding="..."?> declaration and
# XML::LibXML wants the undecoded octets so that declaration stays truthful.
# Returns undef (after logging) when the server cannot be reached.
sub _load_wsdl_xml {
    my ($url) = @_;
    INFO "[$local_filename" . ":" . __LINE__ . "]Fetching WSDL from $url";
    my $res = $ua->get($url);
    unless ($res->is_success) {
	WARN "[$local_filename" . ":" . __LINE__ . "]WSDL fetch failed: " . $res->status_line;
	return undef;
    }
    return $res->content;
}
my $wsdl;

my $wsdl_xml = _load_wsdl_xml($wsdlurl);

unless (defined $wsdl_xml)
  { die "[$local_filename" . ":" . __LINE__ . "]Failed wsdl load $wsdlurl \n"; }

# XML::Compile takes a plain string as a filename; a SCALAR ref is parsed as XML text,
    # which is what keeps the fetched WSDL in memory instead of on disk.
    $wsdl = XML::Compile::WSDL11->new(\$wsdl_xml);
    INFO "[$local_filename" . ":" . __LINE__ . "]wsdl source: $wsdlurl (in memory)";

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('AddPatronNote');
 
unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}

#my ($patronid, $noteid, $name ,$btype, $notedate, $notetype,  $branch,$actdate, $lastbranch, $alias);
my $patronid;

my %AddNote;
my %AddNoteRequest;

%AddNote = (defined $opt_w ? ( NoteType => WITHDRAW_SOFTBLOCK_NOTE_TYPE,
			       NoteText => WITHDRAW_SOFTBLOCK_NOTE_TEXT)
	    :  ( NoteType => GRAD_SOFTBLOCK_NOTE_TYPE,
		 NoteText => GRAD_SOFTBLOCK_NOTE_TEXT)
    );

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

mce_loop {


  my ($mce, $chunk_ref, $chunk_id) = @_;

    foreach my $line (@$chunk_ref) {
        chomp $line;
        next if $line eq '';  # Skip empty lines
	INFO "[$local_filename" . ":" . __LINE__ . "]\n" . "Record $_";

	($patronid)  = split(/,/,$line);

  
	$AddNote{PatronID}= $patronid;

	INFO "[$local_filename" . ":" . __LINE__ . "]AddNoteRequest " . Dumper(\%AddNoteRequest) ;
	
	my ($result1,$trace1)=$call1->(%AddNoteRequest);

	ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result1);
	ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace1);

	if ($trace1->errors) {
	    $trace1->printErrors;
	}
    }
} <> ;

MCE::Loop::finish;


