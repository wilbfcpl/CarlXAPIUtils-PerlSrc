# Author:  <wblake@CB95043>
# Created: May 25, 2026
# Version: 0.01
#
# Usage: perl  settleFinesAndFees.pl [-g] [-p] filename.csv
#  
# -g Logging
# -p Production wsdl file and server
# filename.csv hasPatron barcode, hash177 value, fineamount,finedate,item,name,status,btycode,editdate,actdate
##177XXXXX itemid generated after the item goes lost
# Only the patronid and hashoneseven columns matter but the Input CSV file column order goes:
#$patronid, $hashoneseven, $amount, $finedate,$itemid, $name, $status,$btycode,$street1,$notes,$regdate,$editdate
# from file testSettleFinesAndFees.csv
# 11982022317784,#1770000148013,4,2024-02-12,41982017659293,ALMAZAN NATALIE,*,PUBLIC,2024-04-10,2024-04-08
#
# Debug mode- a lot more SOAP messages.
# MCE Loop has error if first line of in file has column label headings
# Uses local copy of CarlX WSDL file PatronAPI.wsdl for PatronAPI requests
#
# SOAPUI tool can provide a sandbox for the WSDL file and PatronAPI requests.
# Note that API call and response return appear to take one second in real time.
#
# Basecamp links to the script development effort
# https://3.basecamp.com/4369994/buckets/14767943/card_tables/cards/8058857119#__recording_8438576637
# https://3.basecamp.com/3903967/buckets/17115720/messages/4834351264#__recording_8438291685

#Fee Settlement via API Patron API settleFinesAndFees
# needs authentication like CirculationAPI

#Perl script sscSettleFinesAndFees fails if the file format is not ISO 8
#github sscSettleFinesAndFees
#https://github.com/wilbfcpl/CarlXPatronAPI/blob/master/sscSettleFinesAndFees.pl
#needs #177 item numbers to work, old item numbers removed after lost status do not work but are good for tracking in CarlX Clients and Discovery
#    $4.00 credits to the accounts.
    
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
Log::Log4perl->easy_init($DEBUG);

use constant PATRON_MODIFIERS_DEBUG_MODE_ON => 1;
use constant PATRON_MODIFIERS_REPORT_MODE_ON => 1;
use constant PATRON_MODIFIERS_STAFFID_WIL => 'wb0';


use constant INSTITUTE_CODE => 1770;
use constant FCPL_BRANCH=>'HDQ';

use constant WAIVE_COMMENT => 'Processing Fee' ;
use constant SSC_PAYTYPE_WAIVE => 'Waive';
use constant SSC_PAYTYPE_PAY => 'Pay';
use constant SSC_PAYTYPE_CANCEL => 'Cancel';
use constant PAY_METHOD=>'Cash';
use constant PAY_AMOUNT=>23.93;
use constant OCCUR => 1;

our ($opt_u,$opt_x,$opt_g,$opt_p);
getopts('u:x:gp');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $result ;
my $trace;

my $local_filename=$0;

$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

# my $PATRON_FILE=$ARGV[0] || die "[$local_filename" . ":" . __LINE__ . "] file argument error $ARGV[0]\n" ;

# INFO "[$local_filename" . ":" . __LINE__ . "]$PATRON_FILE";

my $wsdlfile =  ( defined $opt_p ?  'PatronAPI.wsdl' : 'PatronAPInew.wsdl');

INFO "[$local_filename" . ":" . __LINE__ . "]wsdlfile: $wsdlfile";

my $wsdl = XML::Compile::WSDL11->new($wsdlfile);

unless (defined $wsdl)
{
    die "[$local_filename" . ":" . __LINE__ . "]Failed XML::Compile call\n" ;
}

my $ua = LWP::UserAgent->new(show_progress=> 1, timeout => 10);#

# my $user = prompt("Username:") ;

my $user = $opt_u ;
my $passwd = $opt_x;


# my $passwd = prompt ("Password:") ;

unless ( (defined $user) and (defined $passwd))
    {
	 die "[$local_filename" . ":" . __LINE__ . "]usage: settleFees -u user  -x passwd \n"
    }


INFO "[$local_filename" . ":" . __LINE__ . "]user $user passwd $passwd\n" ;


sub basic_auth($$)
{
  my ($request, $trace) = @_;
    
   	
  $request->authorization_basic($user, $passwd);
  my $res=$ua->request($request);

  # Handle the response
  if ($res->is_success) {
    INFO  "[$local_filename" . ":" . __LINE__ . "]Auth Success. status: $res->status_line \n";
    INFO  "[$local_filename" . ":" . __LINE__ . "]Auth Success. content: $res->decoded_content \n";
  } else {
      INFO "[$local_filename" . ":" . __LINE__ . "]Auth Fail. status: $res->status_line \n";
     die  "[$local_filename" . ":" . __LINE__ . "]Auth fail. content: $res->decoded_tontent \n";
}

}

INFO "[$local_filename" . ":" . __LINE__ . "] compileClient";

my $call1 = $wsdl->compileClient('SettleFinesAndFees',  transport_hook => \&basic_auth);

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}



my %ResponseStatus;
my %SettleFinesAndFeesRequest;
my %FineOrFee;

%ResponseStatus = (
   Code=>0,
   Severity=>"None",
   ShortMessage=>"No Message",
   LongMessage=>"No Long Message",
   Resolution=>"none"
    );

%FineOrFee = (
         Occur=>OCCUR,
         WaiveComment=>WAIVE_COMMENT,
 PayType =>SSC_PAYTYPE_WAIVE ,
 ResponseStatus=>\%ResponseStatus
 );

%SettleFinesAndFeesRequest =
 (
  SearchType=>'Patron ID',
       FineOrFee=> \%FineOrFee,
       Modifiers => {
       DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
       ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
       StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
       EnvBranch =>FCPL_BRANCH
		    }
      ) ;

# Use MCE::Loop to process lines in parallel
MCE::Loop::init(
    max_workers => 4,
    chunk_size => 1,
    user_error => sub {
        my ($mce, $chunk_id, $error) = @_;
        ERROR "[$local_filename" . ":" . __LINE__ . "] Error in worker $chunk_id: $error";
    }
);


#INFO "[$local_filename" . ":" . __LINE__ . "]Lines array @lines";
mce_loop {
    
    my ($mce, $chunk_ref, $chunk_id) = @_;

       foreach my $line (@$chunk_ref) {
        chomp $line;
        next if $line eq '';  # Skip empty lines
	INFO "[$local_filename" . ":" . __LINE__ . "]\n" . "Record $_";

    
    INFO "[$local_filename" . ":" . __LINE__ . "]Record $_ ";
    my ($patronid, $hashoneseven, $amount)  = split(/,/, $line);

    $FineOrFee{ItemID}= $hashoneseven;
    $FineOrFee{Amount}= $amount;
    $SettleFinesAndFeesRequest{SearchID}=$patronid;

    my ($result1,$trace1)=$call1->(%SettleFinesAndFeesRequest);

    INFO "[$local_filename" . ":" . __LINE__ . "]Record $_" . " Call Completed";

    ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result1);
    ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace1);
    
    if ($trace1->errors) {
       INFO $trace1->printErrors;
    }
       }

    } <> ;

MCE::Loop::finish;
