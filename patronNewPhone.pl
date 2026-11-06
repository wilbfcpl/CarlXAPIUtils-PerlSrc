# Author:  <wblake@CB95043> -*-cperl-*-
# Created: Nov 5, 2026
# Version: 0.02
#
# Usage: perl patronNewPhone.pl [-g] [-x] filename.csv
# Usage: echo "11982021684457" |  perl patronAllowEmail.pl -xg
#
# Options:
# -g Logging Level as TRACE,DEBUG,INFO,WARN,ERROR,FATAL
# -p PRODUCTION SERVER update mode- BE CAREFUL and BE SURE

# filename.csv hasPatron barcode, borrower name, borrower type,and email address
# Input file filename.csv should only have existing Patron Records
#$patronid,$name,$bty,$email
# Note that Allow Email needs an email address in the patron record to "stick."
# Debug mode- a lot more SOAP messages.
# MCE Loop has error if first line of in file has column label headings

#
# SOAPUI tool can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
# An SQL Query to select patrons from an imported table PATRONSDONOTSENDEMAIL
#select sample.name, sample.email, patron.emailnotices from carlreports.PATRONSDONOTSENDEMAIL sample, carlreports.PATRON_V2 patron
#where sample.patronid = patron.patronid order by sample.name;

use strict;
use warnings FATAL => 'all';
use diagnostics;

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
use constant PATRON_MODIFIERS_DEBUG_MODE_ON => 1;
use constant PATRON_MODIFIERS_REPORT_MODE_ON => 1;
use constant PATRON_MODIFIERS_STAFFID_WIL => 'wb0';
use constant FCPL_BRANCH=>'HDQ';
use constant INSTITUTE_CODE => 1770;

#Command line input variable handling
our ($opt_g,$opt_p, $opt_x);
getopts('gpx');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';


# Results and trace from XML::Compile::WSDL et al.
my $result ;
my $trace;

#Instrumentation for Print Messages
my $local_filename=$0;
$local_filename =~ s/.+\\([A-z]+.pl)/$1/;


#See the CPAN and web pages for XML::Compile::WSDL http://perl.overmeer.net/xml-compile/

my $wsdlurl = ( defined $opt_p ? 'http://fcplapp.fcpl.org:8080/CarlXAPI/PatronAPI.wsdl' : 'http://fcplapp.fcpl.org:8081/CarlXAPI/PatronAPI.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlurl: $wsdlurl)";

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

# Fetch the WSDL document raw bytes. ->content rather than ->decoded_content is
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

if (defined $wsdl_xml) {
    # XML::Compile takes a plain string filename; a SCALAR ref is parsed as XML text,
    # which is what keeps the fetched WSDL in memory instead of on disk.
    $wsdl = XML::Compile::WSDL11->new(\$wsdl_xml);
    INFO "[$local_filename" . ":" . __LINE__ . "]wsdl src: $wsdlurl (memory)";
}

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}




my $call1 = $wsdl->compileClient(
    'UpdatePatron',
    kind => 'request-response',
);

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1\n" ;
}


#my ($patronid,$name,$bty,$email) ;
my ($patronid) ;

my %PatronUpdateValues;
my %PatronUpdateRequest;
my $phone1;
my $phone2;

%PatronUpdateRequest =
       (
        SearchType => SEARCHTYPE_PATRONID,
        Patron => \%PatronUpdateValues,
        Modifiers=> {
        DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
        ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
	StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
	EnvBranch =>FCPL_BRANCH
	}
       );

 ERROR "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;


# Use MCE::Loop to process lines in parallel
 MCE::Loop::init(
    max_workers => 16,
    chunk_size => 8,
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

	($patronid,$phone1,$phone2)  = split(/,/,$line);

	%PatronUpdateValues =    $phone2 eq "" ? ( Phone1=>$phone1 ) :
				  ( Phone1=>$phone1,
				    Phone2=>$phone2 );

	INFO "[$local_filename" . ":" . __LINE__ . "]PatronNewPhone Ph1: " . $phone1 . " Ph2: " . defined($phone2) ? $phone2 : "" ;

	$PatronUpdateRequest{SearchID}= $patronid;

	INFO "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;

	my ($result1,$trace1)=$call1->(%PatronUpdateRequest);

	ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result1);
	ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace1);

	if ($trace1->errors) {
	    $trace1->printErrors;
	}
    }

} <>;

MCE::Loop::finish;
