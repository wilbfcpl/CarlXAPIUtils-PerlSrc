# Author:  <wblake@CB95043>
# Created: May 25, 2026
# Version: 0.02
#
# Changelog:
# 0.02 (2026-09-17):
#   - Fixed basic_auth() transport_hook to explicitly `return $res;`. Previously the sub's
#     return value fell through to the last INFO() call in its success branch (a truthy
#     scalar, not the HTTP::Response), so XML::Compile::Transport::SOAPHTTP rejected it with
#     "transport_hook must produce a HTTP::Response, got 1" and every SettleFinesAndFees
#     call silently returned an undef result.
#   - Added ItemBranch (xs:short, minOccurs=0) to the transaction:Transaction complexType in
#     PatronAPInew.wsdl/PatronAPI.wsdl, between Title and TransactionBranch, matching the field
#     actually returned by the live CarlX server. Without it, XML::Compile refused to decode
#     any GetPatronTransactionsResponse item (e.g. LostItem) that included ItemBranch.
#   - GetPatronTransactionsResponse item collections (ChargeItems, ClaimedItems, FineItems,
#     HoldItems, LostItems, OverdueItems, ReserveItems, TraceItems, UnavailableHoldItems) are
#     now flattened from XML::Compile's choice-group shape
#     ({ "cho_<ItemType>" => [ { <ItemType> => {...} } ] }) into plain arrayrefs of item
#     hashrefs via _flatten_choice_items().
#
# Usage: perl  settleFinesAndFees.pl [-g] [-p] filename.csv
#
# Usage:  echo "11982022414417,#1770000158859,15.41" | perl .\settleFinesAndFees.pl -g -u frederick -x mnXYEZYE%T5H7mlPEmgb -r
# -g Logging
# -p Production wsdl file and server
# -r read only
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

#Command line input variable handling g debug, p production mode/production server
# -u user -x password

use constant WAIVE_COMMENT => 'Processing Fee' ;
use constant SSC_PAYTYPE_WAIVE => 'Waive';
use constant SSC_PAYTYPE_PAY => 'Pay';
use constant SSC_PAYTYPE_CANCEL => 'Cancel';
use constant PAY_METHOD=>'Cash';
use constant PAY_AMOUNT=>23.93;
use constant OCCUR => 1;

    
our ($opt_u,$opt_x,$opt_g,$opt_p,$opt_r);
getopts('u:x:gpr');

use if defined $opt_g, "Log::Report", mode=>'DEBUG';

my $read_only_mode = ( defined $opt_r ? 1 : 0);

my $result ;
my $trace;

my $local_filename=$0;

$local_filename =~ s/.+\\([A-z]+.pl)/$1/;

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

  # transport_hook must return the HTTP::Response object, otherwise
  # XML::Compile::Transport::SOAPHTTP fails with
  # "transport_hook must produce a HTTP::Response, got {resp}".
  return $res;
}

my $call1 = $wsdl->compileClient('SettleFinesAndFees',  transport_hook => \&basic_auth);
my $call2 = $wsdl->compileClient('GetPatronTransactions');

unless ( defined $call1 )
{ die "[$local_filename" . ":" . __LINE__ . "] SOAP/WSDL Error $wsdl $call1 \n" ;
}



my %ResponseStatus;
my %SettleFinesAndFeesRequest;
my %FineOrFee;
my %GetPatronTransactionsRequest;
my %GetPatronTransactionsResponse;

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


%GetPatronTransactionsRequest =
 (

  SearchType=>'Patron ID',
  Modifiers => {
      DebugMode=>PATRON_MODIFIERS_DEBUG_MODE_ON,
      ReportMode=>PATRON_MODIFIERS_REPORT_MODE_ON,
      StaffID=>PATRON_MODIFIERS_STAFFID_WIL,
      EnvBranch =>FCPL_BRANCH		    }
      ) ;

# Mirrors the GetPatronTransactionsResponse element from PatronAPInew.wsdl
# (patronAPI:GetPatronTransactionsResponse extends transaction:PatronTransactionSummary).
# ResponseStatuses is an arrayref of response:ResponseStatus hashrefs.
# Each *Items key is an arrayref of the corresponding transaction:*Item hashrefs
# (ChargeItem, ClaimedItem, FineItem, HoldItem, LostItem, OverdueItem, ReserveItem,
# TraceItem, UnavailableHoldItem), each of which extends transaction:Transaction.
# transaction:Transaction now also includes ItemBranch (added to PatronAPInew.wsdl
# between Title and TransactionBranch to match the live CarlX server response), so
# every flattened item hashref below carries an ItemBranch field alongside Branch.
%GetPatronTransactionsResponse = (
    ResponseStatuses      => [],    # response:ResponseStatus[]
    PatronID              => undef,
    AlternateID           => undef,
    GUID                  => undef,
    ChargedItemsCount     => undef,
    ClaimedItemsCount     => undef,
    FineItemsCount        => undef,
    HoldItemsCount        => undef,
    LostItemsCount        => undef,
    OverdueItemsCount     => undef,
    ReserveItemsCount     => undef,
    TraceItemsCount       => undef,
    UnavailableHoldsCount => undef,
    FineTotal             => undef,
    LostItemFeeTotal      => undef,
    ChargeItems           => [],    # transaction:ChargeItem[]
    ClaimedItems          => [],    # transaction:ClaimedItem[]
    FineItems             => [],    # transaction:FineItem[]
    HoldItems             => [],    # transaction:HoldItem[]
    LostItems             => [],    # transaction:LostItem[]
    OverdueItems          => [],    # transaction:OverdueItem[]
    ReserveItems          => [],    # transaction:ReserveItem[]
    TraceItems            => [],    # transaction:TraceItem[]
    UnavailableHoldItems  => [],    # transaction:UnavailableHoldItem[]
    );

# XML::Compile decodes each *Items choice group (maxOccurs="unbounded" xs:choice) as
# { "cho_<ItemType>" => [ { <ItemType> => {...} }, ... ] } rather than a plain array.
# Unwrap that into a flat arrayref of the inner item hashrefs (each including the
# transaction:Transaction fields, e.g. ItemBranch, TransactionBranch, ItemNumber, etc.)
sub _flatten_choice_items {
    my ($group, $item_name) = @_;
    return [] unless ref $group eq 'HASH';
    my $entries = $group->{"cho_$item_name"};
    return [] unless ref $entries eq 'ARRAY';
    return [ map { $_->{$item_name} } @$entries ];
}

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


	if ($read_only_mode==0)
	{   $FineOrFee{ItemID}= $hashoneseven;
	    $FineOrFee{Amount}= $amount;
	    $SettleFinesAndFeesRequest{SearchID}=$patronid;
	   ($result,$trace)=$call1->(%SettleFinesAndFeesRequest);
	}
	else {
	    $GetPatronTransactionsRequest{SearchID}=$patronid;
	    ($result,$trace)=$call2->(%GetPatronTransactionsRequest);

	    if (ref $result eq 'HASH') {
		# XML::Compile::WSDL11 returns the decoded body nested under a key
		# matching the response message part name (GetPatronTransactionsResponse)
		# rather than flattened, so unwrap it before merging into our flat hash.
		my $response_data = (ref $result->{GetPatronTransactionsResponse} eq 'HASH')
		    ? $result->{GetPatronTransactionsResponse}
		    : $result;
		%GetPatronTransactionsResponse = (
		    %GetPatronTransactionsResponse,
		    %$response_data,
		    ChargeItems          => _flatten_choice_items($response_data->{ChargeItems}, 'ChargeItem'),
		    ClaimedItems         => _flatten_choice_items($response_data->{ClaimedItems}, 'ClaimedItem'),
		    FineItems            => _flatten_choice_items($response_data->{FineItems}, 'FineItem'),
		    HoldItems            => _flatten_choice_items($response_data->{HoldItems}, 'HoldItem'),
		    LostItems            => _flatten_choice_items($response_data->{LostItems}, 'LostItem'),
		    OverdueItems         => _flatten_choice_items($response_data->{OverdueItems}, 'OverdueItem'),
		    ReserveItems         => _flatten_choice_items($response_data->{ReserveItems}, 'ReserveItem'),
		    TraceItems           => _flatten_choice_items($response_data->{TraceItems}, 'TraceItem'),
		    UnavailableHoldItems => _flatten_choice_items($response_data->{UnavailableHoldItems}, 'UnavailableHoldItem'),
		    );
		INFO "[$local_filename" . ":" . __LINE__ . "]GetPatronTransactionsResponse: " . Dumper(\%GetPatronTransactionsResponse);
	    }
	}
	
    	
    INFO "[$local_filename" . ":" . __LINE__ . "]Record $_" . " Call Completed";

    ERROR "[$local_filename" . ":" . __LINE__ . "]Result: " . Dumper($result);
    ERROR "[$local_filename" . ":" . __LINE__ . "]Trace: " . Dumper($trace);
    
    if ($trace->errors) {
       INFO $trace->printErrors;
    }
       }

    } <> ;

MCE::Loop::finish;
