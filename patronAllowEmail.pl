# Author:  <wblake@CB95043>
# Created: June 5, 2025
# Version: 0.02
#
# Usage: perl patronAllowEmail.pl [-g] [-x] filename.csv
# Usage: echo "11982021684457" |  perl patronAllowEmail.pl -xg
#
# Options:
# -g Logging Level as TRACE,DEBUG,INFO,WARN,ERROR,FATAL
# -p PRODUCTION SERVER update mode- BE CAREFUL and BE SURE
# -x don't send email

# filename.csv hasPatron barcode, borrower name, borrower type,and email address
# Input file filename.csv should only have existing Patron Records
#$patronid,$name,$bty,$email
# Note that Allow Email needs an email address in the patron record to "stick."
# Debug mode- a lot more SOAP messages.
# MCE Loop has error if first line of in file has column label headings
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for PatronAPI requests
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

my $wsdlfile =  ( defined $opt_p ?  'PatronAPI.wsdl' : 'PatronAPInew.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlfile: $wsdlfile";

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);


unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $call1 = $wsdl->compileClient('UpdatePatron');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1\n" ;
}


#my ($patronid,$name,$bty,$email) ;
my ($patronid) ;

my %PatronUpdateValues;
my %PatronUpdateRequest;

%PatronUpdateValues =
    ( EmailNotices =>  defined($opt_x) ? EMAIL_NOTICE_NO_EMAIL:EMAIL_NOTICE_SEND_EMAIL
      
    );

%PatronUpdateRequest =
       (
        SearchType => SEARCHTYPE_PATRONID,
        Patron => \%PatronUpdateValues,
        Modifiers=> {
        DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
        ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
	StaffID=>PATRON_MODIFIERS_STAFFID_WIL
	}
       );

 ERROR "[$local_filename" . ":" . __LINE__ . "]PatronUpdateRequest " . Dumper(\%PatronUpdateRequest) ;


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
